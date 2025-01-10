#!/bin/sh

set -ex

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
        echo "About to start the ${n}th recording"
        adb shell screenrecord --time-limit 15 --verbose "/sdcard/ui_tests_${n}.mp4"
        echo "Recording ${n} finished"
        ((n++))
    done
}

# Run the recording loop in the background
echo "About to run the recording loop"
record_screen &
recording_pid=$!
# sleep for 5 seconds to make sure the recording loop is started
sleep 5
echo "Recording loop started"

# run tests
echo "About to run tests"
maestro test $workspace/ --format junit --output $BITRISE_DEPLOY_DIR/test_report.xml $additional_params || true
echo "Tests finished"

# Signal the recording loop to stop
echo "About to signal the recording loop to stop"
touch "$RECORDING_DONE_FLAG"
echo "Signal sent"

# Wait for the recording loop to exit
echo "Checking if the recording loop is still running"
if ps -p $recording_pid > /dev/null; then
    echo "Waiting for the recording loop to exit"
    wait $recording_pid
    echo "Recording loop exited"
else
    echo "Recording loop already exited"
fi

echo "Recording files:" && adb shell ls /sdcard/

# Remove the recording flag
rm -f "$RECORDING_DONE_FLAG"

# Collect recordings from the emulator
n=0
recordings=()
echo "Collecting recordings"
while adb shell ls "/sdcard/ui_tests_${n}.mp4" &>/dev/null; do
    echo "Pulling recording ${n}"   
    adb pull "/sdcard/ui_tests_${n}.mp4" "$BITRISE_DEPLOY_DIR/ui_tests_${n}.mp4" 
    echo "Removing recording ${n}"
    adb shell rm "/sdcard/ui_tests_${n}.mp4"
    echo "Recording ${n} pulled"
    recordings+=("$BITRISE_DEPLOY_DIR/ui_tests_${n}.mp4")
    ((n++))
done

echo "Exited the recording loop"
echo "Recordings collected: ${recordings[@]}"

# Kill adb server
adb kill-server
echo "ADB server killed"

# Export test results
# Test report file
# Export test results
echo "About to export test results"
echo "Exporting test results"
if [[ "$export_test_report" == "true" ]]; then
    echo "Creating test run directory"
    test_run_dir="$BITRISE_TEST_RESULT_DIR/maestro"
    mkdir -p "$test_run_dir"

    echo "Copying test report xml"
    cp "$BITRISE_DEPLOY_DIR/test_report.xml" "$test_run_dir/maestro_report.xml"

    # Export recordings
    echo "Exporting recordings"
    for recording in "${recordings[@]}"; do
        echo "Copying recording ${recording}"
        cp "$recording" "$test_run_dir/"
        echo "Recording ${recording} copied"
    done
    echo "Recordings copied"
    # Add metadata fileq
    echo '{"maestro-test-report":"Maestro Android Flows"}' >> "$test_run_dir/test-info.json"
else
    echo "Test report export is disabled."
fi

echo "All tasks completed."