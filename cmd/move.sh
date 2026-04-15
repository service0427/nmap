#!/usr/bin/env bash

SERIAL=$1
COUNT=$2

if [ -z "$SERIAL" ] || [ -z "$COUNT" ]; then
    echo "Usage: ./cmd.sh --move <DEVICE_SERIAL> <COUNT>"
    exit 1
fi

echo "Generating random walk with $COUNT points for $SERIAL..."
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../test_nmap_v1" &> /dev/null && pwd)"

# Ask the device what its current location is
LASTLOC=$(adb -s "$SERIAL" shell su -c "cat /data/data/com.rosteam.gpsemulator/shared_prefs/com.rosteam.gpsemulator_preferences.xml 2>/dev/null | grep lastloc")

if [[ ! "$LASTLOC" =~ "Current_Start+" ]]; then
    echo "Could not find current location for $SERIAL. Is the GPS Emulator running?"
    exit 1
fi

# Extract lat,lng
COORD=$(echo "$LASTLOC" | sed 's/.*Current_Start+//' | cut -d'+' -f1)
LAT=$(echo "$COORD" | cut -d',' -f1)
LNG=$(echo "$COORD" | cut -d',' -f2)

if [ -z "$LAT" ] || [ -z "$LNG" ]; then
    echo "Failed to parse coordinate ($COORD) for device $SERIAL."
    exit 1
fi

echo "Current Location detected: $LAT, $LNG"

# We will write a small python script inline or call a python script to generate points
PYTHON_SCRIPT="$BASE_DIR/utils/random_move_gen.py"

JSON_OUT="/tmp/route_library/random_${SERIAL}.json"
mkdir -p "/tmp/route_library"

python3 "$PYTHON_SCRIPT" "$LAT" "$LNG" "$COUNT" "$JSON_OUT"

if [ ! -f "$JSON_OUT" ]; then
    echo "Failed to generate route JSON."
    exit 1
fi

echo "Rebuilding XML for speed ~30.0 km/h (walking/slow driving)..."
LOCAL_TMP="/tmp/final_1_prefs_${SERIAL}.xml"
python3 "$BASE_DIR/utils/rebuild_xml.py" "$JSON_OUT" "30.0" "$SERIAL" > /dev/null

adb -s "$SERIAL" shell am force-stop "com.rosteam.gpsemulator"

PREFS_NAME="com.rosteam.gpsemulator_preferences.xml"
PREFS_PATH="/data/data/com.rosteam.gpsemulator/shared_prefs/$PREFS_NAME"

adb -s "$SERIAL" push "$LOCAL_TMP" "/data/local/tmp/$PREFS_NAME" >/dev/null 2>&1
adb -s "$SERIAL" shell "su -c 'chmod 660 $PREFS_PATH 2>/dev/null; cp /data/local/tmp/$PREFS_NAME $PREFS_PATH && chown \$(stat -c %u:%g /data/data/com.rosteam.gpsemulator) $PREFS_PATH && chmod 440 $PREFS_PATH'"

rm -f "$LOCAL_TMP"
# rm -f "$JSON_OUT"

echo "Starting GPS mock routing for random movement..."
SPEED_MPS=$(python3 -c "print(round(30.0 / 3.6, 6))")
adb -s "$SERIAL" shell su -c "am start-foreground-service -n com.rosteam.gpsemulator/.servicex2484 -a ACTION_START_CONTINUOUS --es uy.digitools.RUTA 'ruta0' --ef velocidad $SPEED_MPS --ei loopMode 0"

echo "Random move initiated for $SERIAL ($COUNT points, ~30m radius)."
