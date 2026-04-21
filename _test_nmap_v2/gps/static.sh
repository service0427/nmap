#!/bin/bash
# test_nmap_v2/gps/static.sh: Self-contained Static GPS Injector (Standard LAT,LNG)

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: ./static.sh <DEVICE_ID> <LAT> <LNG> [TASK_ID]"
    exit 1
fi

DEVICE_ID=$1
# [STANDARD] $2: Latitude(36.x), $3: Longitude(127.x)
BASE_LAT=$2
BASE_LNG=$3
TASK_ID=${4:-$(date +%Y%m%d%H%M%S)}
PKG_NAME="com.rosteam.gpsemulator"

# 1. Calculate random start point (LAT LNG)
RAND_COORD=$(python3 -c "
import random, math
lat = float($BASE_LAT)
lng = float($BASE_LNG)
min_r = 5.0 / 111.0
max_r = 10.0 / 111.0
r = random.uniform(min_r, max_r)
theta = random.uniform(0, 2 * math.pi)
new_lat = lat + r * math.sin(theta)
new_lng = lng + (r * math.cos(theta)) / math.cos(math.radians(lat))
print(f'{new_lat:.7f},{new_lng:.7f}')
")

TARGET_LAT=$(echo $RAND_COORD | cut -d',' -f1)
TARGET_LNG=$(echo $RAND_COORD | cut -d',' -f2)

echo "======================================================"
echo "🎯 Automated Static GPS (5km~10km Range)"
echo "   Device: $DEVICE_ID | Task: $TASK_ID"
echo "   Input Lat/Lng : $BASE_LAT, $BASE_LNG"
echo "   Output Lat/Lng: $TARGET_LAT, $TARGET_LNG (Korea)"
echo "======================================================"

# 2. Generate XML (Standard order: LATITUDE,LONGITUDE)
cat <<EOF > "/tmp/static_${DEVICE_ID}.xml"
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="noads" value="true" />
    <boolean name="onettimeblock" value="true" />
    <int name="pagbookmark" value="1" />
    <int name="accion" value="0" />
    <float name="velocidad" value="0.3" />
    <string name="ruta0">Static+1+0.3+0.0+${TARGET_LAT},${TARGET_LNG};${TARGET_LAT},${TARGET_LNG};</string>
    <string name="lastloc">Current+${TARGET_LAT},${TARGET_LNG}+15.0</string>
</map>
EOF

# 3. Inject into Device
PREFS_PATH="/data/data/$PKG_NAME/shared_prefs/${PKG_NAME}_preferences.xml"

adb -s "$DEVICE_ID" shell am force-stop "$PKG_NAME"
adb -s "$DEVICE_ID" push "/tmp/static_${DEVICE_ID}.xml" "/data/local/tmp/gps_prefs.xml" >/dev/null 2>&1
adb -s "$DEVICE_ID" shell "su -c 'cp /data/local/tmp/gps_prefs.xml $PREFS_PATH && chown \$(stat -c %u:%g /data/data/$PKG_NAME) $PREFS_PATH && chmod 440 $PREFS_PATH'"

# 4. Start Service
adb -s "$DEVICE_ID" shell su -c "am start-foreground-service -n $PKG_NAME/.servicex2484 -a ACTION_START_CONTINUOUS --es uy.digitools.RUTA 'ruta0' --ef velocidad 0.1 --ei loopMode 1" > /dev/null 2>&1

rm -f "/tmp/static_${DEVICE_ID}.xml"
echo "[✓] GPS successfully initialized in Korea."
