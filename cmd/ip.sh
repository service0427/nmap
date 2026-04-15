#!/usr/bin/env bash

echo "Toggling Airplane Mode to update IP..."

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

for serial in $devices; do
    echo "[$serial] Turning Airplane Mode ON..."
    # Enable Airplane Mode via root cmd connectivity
    adb -s "$serial" shell su -c "cmd connectivity airplane-mode enable"
done

echo "Waiting 3 seconds to ensure connection drops..."
sleep 3

for serial in $devices; do
    echo "[$serial] Turning Airplane Mode OFF..."
    # Disable Airplane Mode via root cmd connectivity
    adb -s "$serial" shell su -c "cmd connectivity airplane-mode disable"
done

echo "IP toggle complete."
