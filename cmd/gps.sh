#!/usr/bin/env bash

TARGET_ID=$1

if [ -z "$TARGET_ID" ]; then
    echo "Usage: ./cmd.sh --gps <TARGET_ID>"
    exit 1
fi

echo "Starting GPS Simulation for Target: $TARGET_ID on all connected devices..."

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

# Switch directory to test_nmap_v1 because run_gps_multi.sh relies on python scripts in utils/
NMAP_V1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../test_nmap_v1" &> /dev/null && pwd)"

for serial in $devices; do
    echo "[$serial] Launching GPS spoofing for target $TARGET_ID..."
    ( cd "$NMAP_V1_DIR" && bash utils/run_gps_multi.sh "$serial" "$TARGET_ID" ) &
done

wait
echo "GPS injection triggered for all devices."
