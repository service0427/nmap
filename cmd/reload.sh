#!/usr/bin/env bash

TARGET=$1

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../test_nmap_v1" &> /dev/null && pwd)"
PKG_NAME="com.rosteam.gpsemulator"

echo "========================================================"
echo "🚑 [경로 재탐색] 최신 잔여 경로 추출 및 GPS 강제 리로드 중..."
echo "========================================================"

for serial in $devices; do
    if [ -n "$TARGET" ] && [ "$serial" != "$TARGET" ]; then
        continue
    fi
    
    echo "--------------------------------------------------------"
    echo "[$serial] Extracting latest remaining route..."
    
    ROUTE_INFO=$(python3 "$BASE_DIR/utils/parse_remaining_route.py" "$serial" 2>&1)
    
    ROUTE_PATH=$(echo "$ROUTE_INFO" | grep "ROUTE_FILE:" | awk '{print $2}')
    DISTANCE=$(echo "$ROUTE_INFO" | grep "TOTAL_DISTANCE:" | awk '{print $2}')
    
    if [ -z "$ROUTE_PATH" ] || [ -z "$DISTANCE" ]; then
        echo -e "\e[1;31m [!] Failed to extract remaining route for $serial!\e[0m"
        echo "$ROUTE_INFO"
        continue
    fi
    
    # Calculate a random speed between 40 and 60 km/h
    TARGET_KMH=$(python3 -c "import random; print(round(random.uniform(90.0, 110.0), 1))")
    
    echo "    > Remaining Distance: $DISTANCE km | Auto-Speed: $TARGET_KMH km/h"
    
    adb -s "$serial" shell am force-stop "$PKG_NAME"
    
    LOCAL_TMP="/tmp/final_1_prefs_${serial}.xml"
    PREFS_NAME="${PKG_NAME}_preferences.xml"
    PREFS_PATH="/data/data/$PKG_NAME/shared_prefs/$PREFS_NAME"
    
    python3 "$BASE_DIR/utils/rebuild_xml.py" "$ROUTE_PATH" "$TARGET_KMH" "$serial" > /dev/null
    
    if [ ! -f "$LOCAL_TMP" ]; then
        echo -e "\e[1;31m [!] Failed to build XML for $serial!\e[0m"
        continue
    fi
    
    echo "[$serial] Injecting data to device..."
    adb -s "$serial" push "$LOCAL_TMP" "/data/local/tmp/$PREFS_NAME" >/dev/null 2>&1
    adb -s "$serial" shell "su -c 'chmod 660 $PREFS_PATH 2>/dev/null; cp /data/local/tmp/$PREFS_NAME $PREFS_PATH && chown \$(stat -c %u:%g /data/data/$PKG_NAME) $PREFS_PATH && chmod 440 $PREFS_PATH'"
    
    rm -f "$LOCAL_TMP"
    rm -f "$ROUTE_PATH"
    
    echo "[$serial] Auto-Starting GPS Engine (Headless)..."
    SPEED_MPS=$(python3 -c "print(round($TARGET_KMH / 3.6, 6))")
    
    adb -s "$serial" shell su -c "am start-foreground-service -n $PKG_NAME/.servicex2484 -a ACTION_START_CONTINUOUS --es uy.digitools.RUTA 'ruta0' --ef velocidad $SPEED_MPS --ei loopMode 0" > /dev/null 2>&1
    
    echo -e "\e[1;32m [✓] GPS EMULATION INJECTED AND STARTED FOR $serial!\e[0m"
done

echo "--------------------------------------------------------"
echo "All done."
