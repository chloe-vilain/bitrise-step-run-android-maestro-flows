#!/bin/sh

set -ex

# Change to source directory
cd $BITRISE_SOURCE_DIR

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
    while [[ ! -f "$recording_done_flag" ]]; do
        adb shell screenrecord --time-limit 15 "/sdcard/ui_tests_${n}.mp4"
        ((n++))
    done
}

# Run the recording loop in the background
record_screen &
recording_pid=$!

# run tests
maestro test $workspace/ --format junit --output $BITRISE_DEPLOY_DIR/test_report.xml $additional_params || true

# Signal the recording loop to stop
touch "$recording_done_flag"

# Wait for the recording loop to exit
wait $recording_pid

# Remove the recording flag
rm -f "$recording_done_flag"

# Collect recordings from the emulator
n=0
recordings=()
while adb shell ls "/sdcard/ui_tests_${n}.mp4" &>/dev/null; do
    adb pull "/sdcard/ui_tests_${n}.mp4" "$BITRISE_DEPLOY_DIR/ui_tests_${n}.mp4"
    adb shell rm "/sdcard/ui_tests_${n}.mp4"
    recordings+=("$BITRISE_DEPLOY_DIR/ui_tests_${n}.mp4")
    ((n++))
done



# Export test results
# Test report file
# Export test results
if [[ "$export_test_report" == "true" ]]; then
    test_run_dir="$BITRISE_TEST_RESULT_DIR/maestro"
    mkdir -p "$test_run_dir"
    cp "$BITRISE_DEPLOY_DIR/test_report.xml" "$test_run_dir/maestro_report.xml"

    # Export recordings
    for recording in "${recordings[@]}"; do
        cp "$recording" "$test_run_dir/"
    done

    # Add metadata file
    echo '{"maestro-test-report":"Maestro Android Flows"}' >> "$test_run_dir/test-info.json"
else
    echo "Test report export is disabled."
fi

echo "All tasks completed."