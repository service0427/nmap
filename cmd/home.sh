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
    
    # 2. Swipe up from bottom to top to dismiss "Accidental touch protection" or lock screen
    # format: input swipe <x1> <y1> <x2> <y2> [duration(ms)]
    adb -s "$serial" shell input swipe 500 1500 500 200 300
    
    # Optional short delay to let the animation play out
    sleep 0.5
    
    # 3. Press HOME key
    adb -s "$serial" shell input keyevent 3
done

echo "Done."
