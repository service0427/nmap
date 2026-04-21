#!/bin/bash
# test_nmap_v2/gps/runner.sh: GPS Emulation Orchestrator

DEVICE_ID=$1
TASK_ID=${2:-"Unknown"}
TARGET_LAT=$3
TARGET_LNG=$4

if [ -z "$DEVICE_ID" ] || [ -z "$TARGET_LAT" ] || [ -z "$TARGET_LNG" ]; then
    echo "[!] Usage: ./runner.sh <DEVICE_ID> <TASK_ID> <LAT> <LNG>"
    exit 1
fi

PKG_NAME="com.rosteam.gpsemulator"

# [1] 기기 연결 확인
if ! adb -s "$DEVICE_ID" shell pm list packages | grep -q "$PKG_NAME"; then
    echo " [!] CRITICAL: $PKG_NAME is not installed on $DEVICE_ID!"
    exit 1
fi

echo "============================================================"
echo "   GPS EMULATOR DYNAMIC ROUTE & SPEED (V2 AUTOMATED)"
echo "   Device: $DEVICE_ID | Task: $TASK_ID | Goal: ($TARGET_LAT, $TARGET_LNG)"
echo "============================================================"

# [2] 경로 생성 (generator.py 호출)
# 병렬 실행 시 파일 충돌 방지를 위해 기기ID와 태스크ID 조합 사용
UNIQUE_FNAME="route_${DEVICE_ID}_${TASK_ID}.json"
echo "[-] Calling GPS Generator for $DEVICE_ID..."
ROUTE_INFO=$(python3 gps/generator.py "$TARGET_LAT" "$TARGET_LNG" "$TASK_ID" "$UNIQUE_FNAME")

ROUTE_PATH=$(echo "$ROUTE_INFO" | grep "ROUTE_FILE:" | awk '{print $2}')
DISTANCE=$(echo "$ROUTE_INFO" | grep "TOTAL_DISTANCE:" | awk '{print $2}')

if [ -z "$ROUTE_PATH" ] || [ -z "$DISTANCE" ]; then
    echo " [!] Error: GPS Generator failed for $DEVICE_ID. Check API/Logs."
    exit 1
fi

# [3] 속도 계산 (5~8분 주행 목적)
REQUIRED_SPEED=$(python3 -c "
import random
dist = float('$DISTANCE')
target_mins = random.uniform(5.0, 8.0)
target_hours = target_mins / 60.0
calc_speed = dist / target_hours
final_speed = max(min(calc_speed, 110.0), 20.0)
print(round(final_speed, 1))
")
echo "    > Generated Distance: $DISTANCE km | Target Speed: $REQUIRED_SPEED km/h"

# [4] XML 프리셋 재구축 및 기기 주입
echo "[-] Injecting GPS Data into $DEVICE_ID..."
adb -s "$DEVICE_ID" shell am force-stop "$PKG_NAME"

LOCAL_TMP="/tmp/prefs_${DEVICE_ID}_${TASK_ID}.xml"
# rebuild_xml.py <ROUTE_JSON> <SPEED_KMH> <DEVICE_ID> <OUTPUT_PATH>
python3 utils/rebuild_xml.py "$ROUTE_PATH" "$REQUIRED_SPEED" "$DEVICE_ID" "$LOCAL_TMP" > /dev/null

PREFS_NAME="${PKG_NAME}_preferences.xml"
PREFS_PATH="/data/data/$PKG_NAME/shared_prefs/$PREFS_NAME"

# 기기 내 임시 경로로 푸시 후 su 권한으로 복사 및 권한 설정 (v1 방식 복구)
adb -s "$DEVICE_ID" push "$LOCAL_TMP" "/data/local/tmp/$PREFS_NAME" >/dev/null 2>&1
adb -s "$DEVICE_ID" shell "su -c 'chmod 660 $PREFS_PATH 2>/dev/null; cp /data/local/tmp/$PREFS_NAME $PREFS_PATH && chown \$(stat -c %u:%g /data/data/$PKG_NAME) $PREFS_PATH && chmod 440 $PREFS_PATH'"

# [5] GPS 엔진 구동 (Headless Intent)
SPEED_MPS=$(python3 -c "print(round($REQUIRED_SPEED / 3.6, 6))")
adb -s "$DEVICE_ID" shell su -c "am start-foreground-service -n $PKG_NAME/.servicex2484 -a ACTION_START_CONTINUOUS --es uy.digitools.RUTA 'ruta0' --ef velocidad $SPEED_MPS --ei loopMode 0"

# [6] 정리
rm -f "$LOCAL_TMP"
rm -f "$ROUTE_PATH"

echo "============================================================"
echo " [✓] GPS EMULATION STARTED FOR $DEVICE_ID!"
echo "============================================================"
