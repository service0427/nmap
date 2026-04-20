#!/bin/bash
# test_nmap_v2: Smart App Status Checker (Foreground Aware)

PKG_NAME="com.nhn.android.nmap"

echo "============================================================"
echo "   NMAP V2 DEVICE & APP STATUS CHECKER (V2)"
echo "   Checking: Foreground Activity vs Background Process"
echo "============================================================"

DEVICES=$(adb devices | grep -w "device" | awk '{print $1}')

if [ -z "$DEVICES" ]; then
    echo -e "\e[1;31m[!] No devices connected via ADB.\e[0m"
    exit 1
fi

echo "[*] Connected Devices Status:"
for DEV_ID in $DEVICES; do
    echo -n "  - [$DEV_ID]: "
    
    # 1. Check if process exists at all
    PID=$(adb -s "$DEV_ID" shell "pidof $PKG_NAME" 2>/dev/null | tr -d '\r\n')
    
    if [ -z "$PID" ]; then
        echo -e "\e[1;30mSTOPPED (Dead)\e[0m"
        continue
    fi

    # 2. Check if it's in the FOREGROUND (Active on screen)
    # We look for the resumed activity or current focus
    IS_FOREGROUND=$(adb -s "$DEV_ID" shell "dumpsys activity activities | grep -E 'mResumedActivity|mCurrentFocus|topResumedActivity' | grep $PKG_NAME" 2>/dev/null)
    
    if [ -n "$IS_FOREGROUND" ]; then
        echo -e "\e[1;32mRUNNING (ACTIVE - PID: $PID)\e[0m"
    else
        echo -e "\e[1;33mBACKGROUND (IDLE - PID: $PID)\e[0m"
    fi
done
echo "============================================================"
