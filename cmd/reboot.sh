#!/usr/bin/env bash

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

echo "Initiating system reboot for all connected devices..."

for serial in $devices; do
    echo "[$serial] Sending reboot command..."
    adb -s "$serial" reboot &
done

wait
echo "All connected devices are now rebooting."
