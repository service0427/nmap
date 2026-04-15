#!/usr/bin/env bash

echo "Muting all audio streams on connected devices..."

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

for serial in $devices; do
    echo "[$serial] Muting sounds..."
    # Stream types: 1=System, 2=Ring, 3=Music, 4=Alarm, 5=Notification
    for stream in 1 2 3 4 5; do
        adb -s "$serial" shell cmd media_session volume --stream $stream --set 0 >/dev/null 2>&1 || true
    done
done

echo "Done."
