#!/bin/sh

set -ex

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Restart ADB server to ensure no conflicts 
adb kill-server && adb start-server

# Change to source directory
cd $BITRISE_SOURCE_DIR
RECORDING_DONE_FLAG="/tmp/recording_done"

# Maestro version
if [[ -z "$maestro_cli_version" ]]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Maestro CLI version not specified, using latest"
else
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Maestro CLI version: $maestro_cli_version"
    export MAESTRO_VERSION=$maestro_cli_version;
fi

# Install maestro CLI
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Installing Maestro CLI"
curl -Ls "https://get.maestro.mobile.dev" | bash
export PATH="$PATH":"$HOME/.maestro/bin"
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") MAESTRO INSTALLED - Check Version"
maestro -v


# install the app
adb install -r $app_file

# Start screen recording in a loop
record_screen() {
    local n=0
    while true; do
        if [ -f "$RECORDING_DONE_FLAG" ]; then
            break
        fi
        adb shell screenrecord --time-limit 15 --verbose "/sdcard/ui_tests_${n}.mp4"
        n=$((n + 1))
    done
}

# Run the recording loop in the background
record_screen &
recording_pid=$!
# sleep for 5 seconds to make sure the recording loop is started
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording loop started"
# sleep 5


# run tests
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") About to run tests"
maestro test $workspace/ --format $export_test_result_format --output $BITRISE_DEPLOY_DIR/test_report.xml $additional_params
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Tests finished"

# Signal the recording loop to stop
touch "$RECORDING_DONE_FLAG"

# Wait for the recording loop to exit
if ps -p $recording_pid > /dev/null; then
    wait $recording_pid
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording loop exited"
else
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording loop already exited"
fi

echo "$(date "+%Y-%m-%d %H:%M:%S.%3N")Recording files:" && adb shell ls /sdcard/ui_tests_*.mp4

# Remove the recording flag
rm -f "$RECORDING_DONE_FLAG"

# Sleep for 5 seconds to make sure the recording loop is exited
# echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Sleeping for 5 seconds to make sure the recording loop is exited"
# sleep 5

# Collect recordings from the emulator
n=0
recordings=()
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Collecting recordings from emulator"
while adb shell ls "/sdcard/ui_tests_${n}.mp4" &>/dev/null; do
    adb pull "/sdcard/ui_tests_${n}.mp4" "$BITRISE_DEPLOY_DIR/ui_tests_${n}.mp4" && echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording ${n} pulled" || {
        echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Error: Failed to pull /sdcard/ui_tests_${n}.mp4"
        break
    }
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Removing recording ${n}"
    adb shell rm "/sdcard/ui_tests_${n}.mp4" && echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording ${n} removed" || {
        echo "Error: Failed to remove /sdcard/ui_tests_${n}.mp4"
        break
    }
    
    recordings+=("$BITRISE_DEPLOY_DIR/ui_tests_${n}.mp4")
    n=$((n + 1))
done

echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recordings collected: ${recordings[@]}"

# Kill adb server
adb kill-server
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") ADB server killed"

# Merge recordings with ffmpeg
merged_video="$BITRISE_DEPLOY_DIR/merged_ui_tests.mp4"
file_list="/tmp/file_list.txt"
rm -f "$file_list"

echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Generating file list for ffmpeg"
for recording in "${recordings[@]}"; do
    echo "file '$recording'" >> "$file_list"
done

echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Running ffmpeg to concatenate videos"

if ffmpeg -f concat -safe 0 -i "$file_list" -c copy "$merged_video"; then
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Videos concatenated successfully into $merged_video"
else
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Error: Failed to concatenate videos"
fi

echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Exporting test results"
if [[ "$export_test_report" == "true" ]]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Creating test run directory"
    test_run_dir="$BITRISE_TEST_RESULT_DIR/maestro"
    mkdir -p "$test_run_dir"

    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Copying test report xml"
    cp "$BITRISE_DEPLOY_DIR/test_report.xml" "$test_run_dir/maestro_report.xml"

    # Export recordings
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Exporting recordings"
    # Copy merged video, if available
    if [[ -f "$merged_video" ]]; then
        cp "$merged_video" "$test_run_dir/"
        echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Merged video copied"
    else
        echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Merged video not found, copying individual recordings"
        for recording in "${recordings[@]}"; do
            cp "$recording" "$test_run_dir/"
            echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording ${recording} copied"
        done
    fi
    echo '{"maestro-test-report":"Maestro Android Flows"}' >> "$test_run_dir/test-info.json"
else
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Test report export is disabled."
fi

echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") All tasks completed."