#!/usr/bin/env bash

echo "Disabling MTP Popups on all devices..."

devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

for serial in $devices; do
    echo "[$serial] Disabling MTP packages..."
    adb -s "$serial" shell pm disable-user --user 0 com.samsung.android.mtp >/dev/null 2>&1 || true
    adb -s "$serial" shell pm disable-user --user 0 com.samsung.android.mtpapplication >/dev/null 2>&1 || true
    adb -s "$serial" shell pm disable-user --user 0 com.android.mtp >/dev/null 2>&1 || true
done

echo "Done."
