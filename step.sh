#!/bin/sh

set -ex

# Restart ADB server to ensure no conflicts 
adb kill-server && adb start-server

# Change to source directory
cd $BITRISE_SOURCE_DIR
RECORDING_DONE_FLAG="/tmp/recording_done"

# Set Maestro CLI version & install maestro CLI
if [[ -z "$maestro_cli_version" ]]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Maestro CLI version not specified, using latest"
else
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Maestro CLI version: $maestro_cli_version"
    export MAESTRO_VERSION=$maestro_cli_version;
fi
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Installing Maestro CLI"
curl -Ls "https://get.maestro.mobile.dev" | bash
export PATH="$PATH":"$HOME/.maestro/bin"
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") MAESTRO INSTALLED - Check Version"
maestro -v


# install the app
adb install -r $app_file

# Run the recording loop in the background
record_screen() {
    local n=0
    while true; do
        if [ -f "$RECORDING_DONE_FLAG" ]; then
            break
        fi
        adb shell screenrecord --time-limit 15 "/sdcard/ui_tests_${n}.mp4"
        n=$((n + 1))
    done
}
record_screen &
recording_pid=$!
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording loop started"


# run tests
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") About to run tests"
maestro test $workspace/ --format $export_test_result_format --output $BITRISE_DEPLOY_DIR/test_report.xml $additional_params
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Tests finished"

# Signal the recording loop to stop and wait for it to exit
touch "$RECORDING_DONE_FLAG"
if ps -p $recording_pid > /dev/null; then
    wait $recording_pid
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording loop exited"
else
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording loop already exited"
fi
# Remove the recording flag
rm -f "$RECORDING_DONE_FLAG"
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording files:" && adb shell ls /sdcard/ui_tests_*.mp4

# Collect recordings from the emulator
n=0
recordings=()
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Collecting recordings from emulator & removing them from the emulator"
while adb shell ls "/sdcard/ui_tests_${n}.mp4" &>/dev/null; do
    adb pull "/sdcard/ui_tests_${n}.mp4" "$BITRISE_DEPLOY_DIR/ui_tests_${n}.mp4" && echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording ${n} pulled" || {
        echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Error: Failed to pull /sdcard/ui_tests_${n}.mp4"
        break
    }
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

# Generate file manifest for ffmpeg
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Generating file list for ffmpeg"
merged_video="$BITRISE_DEPLOY_DIR/merged_ui_tests.mp4"
file_list="/tmp/file_list.txt"
rm -f "$file_list"
for recording in "${recordings[@]}"; do
    echo "file '$recording'" >> "$file_list"
done

# Merge recordings with ffmpeg
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Running ffmpeg to concatenate videos"
if ffmpeg -f concat -safe 0 -i "$file_list" -c copy "$merged_video"; then
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Videos concatenated successfully into $merged_video"
    # Remove recording segments from the deploy directory
    for recording in "${recordings[@]}"; do
        echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Removing recording segment $recording"
        rm -f "$recording"
    done
else
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Error: Failed to concatenate videos"
fi

echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") All tasks completed."

