#!/usr/bin/env bash

echo "Sending HOME sequence (Wake -> Swipe Up -> Home) to all connected devices..."

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

for serial in $devices; do
    echo "[$serial] Bypassing lock/touch-protection and going Home..."
    
    # 1. Wake up the screen (in case it's asleep)
    adb -s "$serial" shell input keyevent 224
    
    # 2. Robust Lock Screen Dismiss
    adb -s "$serial" shell wm dismiss-keyguard >/dev/null 2>&1
    
    # 3. Disable MTP (Data Sync) Popups to prevent visual blocking
    adb -s "$serial" shell pm disable-user --user 0 com.samsung.android.mtp >/dev/null 2>&1 || true
    adb -s "$serial" shell pm disable-user --user 0 com.samsung.android.mtpapplication >/dev/null 2>&1 || true
    adb -s "$serial" shell pm disable-user --user 0 com.android.mtp >/dev/null 2>&1 || true
    
    # 4. Swipe up from bottom to top to dismiss "Accidental touch protection"
    # format: input swipe <x1> <y1> <x2> <y2> [duration(ms)]
    adb -s "$serial" shell input swipe 500 1500 500 200 300
    
    # Optional short delay to let the animation play out
    sleep 0.5
    
    # 5. Press HOME key
    adb -s "$serial" shell input keyevent 3
done

echo "Done."
