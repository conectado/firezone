#!/usr/bin/env bash
# This script must run from an elevated shell so that Firezone won't try to elevate

set -euo pipefail

BUNDLE_ID="dev.firezone.client"
DUMP_PATH="$LOCALAPPDATA/$BUNDLE_ID/data/logs/last_crash.dmp"
PACKAGE=firezone-gui-client

# This prevents a `shellcheck` lint warning about using an unset CamelCase var
if [[ -z "$ProgramData" ]]; then
    echo "The env var \$ProgramData should be set to \`C:\ProgramData\` or similar"
    exit 1
fi

function smoke_test() {
    # Make sure the files we want to check don't exist on the system yet
    stat "$LOCALAPPDATA/$BUNDLE_ID" && exit 1
    stat "$ProgramData/$BUNDLE_ID" && exit 1

    # Run the smoke test normally
    cargo run -p "$PACKAGE" -- smoke-test

    # Make sure the files were written in the right paths
    stat "$LOCALAPPDATA/$BUNDLE_ID/config/advanced_settings.json"
    stat "$LOCALAPPDATA/$BUNDLE_ID/data/logs/"connlib*log
    stat "$LOCALAPPDATA/$BUNDLE_ID/data/wintun.dll"
    stat "$ProgramData/$BUNDLE_ID/config/device_id.json"
}

function crash_test() {
    # Delete the crash file if present
    rm -f "$DUMP_PATH"

    # Fail if it returns success, this is supposed to crash
    cargo run -p "$PACKAGE" -- --crash && exit 1

    # Fail if the crash file wasn't written
    stat "$DUMP_PATH"
}

function get_stacktrace() {
    # Per `crash_handling.rs`
    SYMS_PATH="../target/debug/firezone-gui-client.syms"
    cargo install --locked dump_syms minidump-stackwalk
    dump_syms ../target/debug/firezone_gui_client.pdb ../target/debug/firezone-gui-client.exe --output "$SYMS_PATH"
    ls ../target/debug
    minidump-stackwalk --symbols-path "$SYMS_PATH" "$DUMP_PATH"
}

smoke_test
crash_test
get_stacktrace

# Clean up
rm "$DUMP_PATH"