#!/usr/bin/env bash

echo "Bypassing Samsung's Data Usage Popup and enabling LTE/5G always..."

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

for serial in $devices; do
    echo "[$serial] Applying Mobile Data Bypass..."
    
    # 1. Force global mobile data to ON
    adb -s "$serial" shell settings put global mobile_data 1
    
    # 2. Disable the Samsung Carrier Data Warning Popup Activity via Root
    adb -s "$serial" shell su -c "pm disable com.samsung.android.app.telephonyui/.carrierui.networkui.app.AllowDataConnectionDialogActivity 2>/dev/null"
    
    # 3. Force-close any currently open data popups just in case
    adb -s "$serial" shell am force-stop com.samsung.android.app.telephonyui 2>/dev/null
done

echo "Done."
