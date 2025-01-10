#!/bin/sh

set -ex

# Restart ADB server to ensure no conflicts 
adb kill-server && adb start-server

# Change to source directory
cd $BITRISE_SOURCE_DIR
RECORDING_DONE_FLAG="/tmp/recording_done"

# Maestro version
if [[ -z "$maestro_cli_version" ]]; then
    echo "Maestro CLI version not specified, using latest"
else
    echo "Maestro CLI version: $maestro_cli_version"
    export MAESTRO_VERSION=$maestro_cli_version;
fi

# Install maestro CLI
echo "Installing Maestro CLI"
curl -Ls "https://get.maestro.mobile.dev" | bash
export PATH="$PATH":"$HOME/.maestro/bin"
echo "MAESTRO INSTALLED - Check Version"
maestro -v

# install the app
adb install -r $app_file

# Start screen recording in a loop
record_screen() {
    local n=0
    while [[ ! -f "$RECORDING_DONE_FLAG" ]]; do
        echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") About to start the ${n}th recording"
        adb shell screenrecord --time-limit 15 --verbose "/sdcard/ui_tests_${n}.mp4"
        echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording ${n} finished"
        ((n++))
    done
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording loop exited"
}

# Run the recording loop in the background
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") About to run the recording loop"
record_screen &
recording_pid=$!
# sleep for 5 seconds to make sure the recording loop is started
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N")Recording loop started"
sleep 5


# run tests
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") About to run tests"
maestro test $workspace/ --format junit --output $BITRISE_DEPLOY_DIR/test_report.xml $additional_params || true
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Tests finished"

# Signal the recording loop to stop
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") About to signal the recording loop to stop"
touch "$RECORDING_DONE_FLAG"
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Signal sent"

# Wait for the recording loop to exit
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Checking if the recording loop is still running"
if ps -p $recording_pid > /dev/null; then
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Waiting for the recording loop to exit"
    wait $recording_pid
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording loop exited"
else
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording loop already exited"
fi

echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording files:" && adb shell ls /sdcard/

# Remove the recording flag
rm -f "$RECORDING_DONE_FLAG"

# Sleep for 5 seconds to make sure the recording loop is exited
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Sleeping for 5 seconds to make sure the recording loop is exited"
sleep 5

# Collect recordings from the emulator
n=0
recordings=()
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Collecting recordings"
while adb shell ls "/sdcard/ui_tests_${n}.mp4" &>/dev/null; do
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Pulling recording ${n}"   
    adb pull "/sdcard/ui_tests_${n}.mp4" "$BITRISE_DEPLOY_DIR/ui_tests_${n}.mp4" && echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording ${n} pulled" || {
        echo "Error: Failed to pull /sdcard/ui_tests_${n}.mp4"
        break
    }
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Removing recording ${n}"
    adb shell rm "/sdcard/ui_tests_${n}.mp4" && echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording ${n} removed" || {
        echo "Error: Failed to remove /sdcard/ui_tests_${n}.mp4"
        break
    }
    
    recordings+=("$BITRISE_DEPLOY_DIR/ui_tests_${n}.mp4")
    ((n++))
done

echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Exited the recording loop"
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recordings collected: ${recordings[@]}"

# Kill adb server
adb kill-server
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") ADB server killed"

# Export test results
# Test report file
# Export test results
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") About to export test results"
echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Exporting test results"
if [[ "$export_test_report" == "true" ]]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Creating test run directory"
    test_run_dir="$BITRISE_TEST_RESULT_DIR/maestro"
    mkdir -p "$test_run_dir"

    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Copying test report xml"
    cp "$BITRISE_DEPLOY_DIR/test_report.xml" "$test_run_dir/maestro_report.xml"

    # Export recordings
    echo "Exporting recordings"
    for recording in "${recordings[@]}"; do
        echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Copying recording ${recording}"
        cp "$recording" "$test_run_dir/"
        echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recording ${recording} copied"
    done
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Recordings copied"
    # Add metadata fileq
    echo '{"maestro-test-report":"Maestro Android Flows"}' >> "$test_run_dir/test-info.json"
else
    echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") Test report export is disabled."
fi

echo "$(date "+%Y-%m-%d %H:%M:%S.%3N") All tasks completed."