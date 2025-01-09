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

# Run Maestro Cloud
adb install -r $app_file
# Kill any existing screenrecord process
adb shell killall screenrecord || echo "No screenrecord process to kill"
# Start recording
adb shell screenrecord --time-limit 60 /sdcard/ui_tests.mp4 &
adb_pid=$!
# Run tests
maestro test $workspace/ --format junit --output $BITRISE_DEPLOY_DIR/test_report.xml $additional_params || true
# Kill screenrecord & surpress errors
# adb shell killall -INT screenrecord || true
# adb shell pkill -INT screenrecord
# Wait for screenrecord to finish
wait $adb_pid
adb pull /sdcard/ui_tests.mp4 $BITRISE_DEPLOY_DIR/ui_tests.mp4
adb shell rm /sdcard/ui_tests.mp4



# Export test results
# Test report file
[[ "$export_test_report" == "true" ]] && is_export="true"
if [[ "$is_export" == "true" ]]; then
    test_run_dir="$BITRISE_TEST_RESULT_DIR/maestro"
    mkdir -p "$test_run_dir"
    cp $BITRISE_DEPLOY_DIR/test_report.xml "$test_run_dir/maestro_report.xml"
    if [[ -f "$BITRISE_DEPLOY_DIR/ui_tests.mp4" ]]; then
        cp $BITRISE_DEPLOY_DIR/ui_tests.mp4 "$test_run_dir/ui_tests.mp4"
    else
        echo "Video file not found: $BITRISE_DEPLOY_DIR/ui_tests.mp4"
    fi
    echo '{"maestro-test-report":"Maestro Android Flows"}' >> "$test_run_dir/test-info.json"
fi