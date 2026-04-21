#!/bin/bash
# test_nmap_v2: Simplified Automated Single Device Launcher

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$BASE_DIR" || exit 1

DEV_ID=$1
if [ -z "$DEV_ID" ]; then
    echo "Usage: ./run.sh R3CN10BZ7PD"
    exit 1
fi

PKG_NAME="com.nhn.android.nmap"
GPS_PKG="com.rosteam.gpsemulator"
CYAN="\e[1;36m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
MAGENTA="\e[1;35m"
NC="\e[0m"

# [1] Fetch Task from API (Single Source of Truth)
API_BASE="http://localhost:5003/api/v1"
echo -e "${YELLOW}[*] Requesting Automated Task from API for: $DEV_ID...${NC}"

API_RESPONSE=$(curl -s "$API_BASE/request?device_id=$DEV_ID")
STATUS=$(echo "$API_RESPONSE" | jq -r '.status')

if [ "$STATUS" != "ok" ]; then
    echo -e "${MAGENTA}[-] No tasks or API error ($STATUS). Exiting...${NC}"
    exit 1
fi

TASK_ID=$(echo "$API_RESPONSE" | jq -r '.task_id')
TARGET_NAME=$(echo "$API_RESPONSE" | jq -r '.name')
TARGET_ADDRESS=$(echo "$API_RESPONSE" | jq -r '.address')
TARGET_LAT=$(echo "$API_RESPONSE" | jq -r '.lat')
TARGET_LNG=$(echo "$API_RESPONSE" | jq -r '.lng')

# Baseline info
ORIG_SSAID=$(echo "$API_RESPONSE" | jq -r '.baseline.ssaid')
ORIG_ADID=$(echo "$API_RESPONSE" | jq -r '.baseline.adid')
ORIG_IDFV=$(echo "$API_RESPONSE" | jq -r '.baseline.idfv')
ORIG_NI=$(echo "$API_RESPONSE" | jq -r '.baseline.ni')
ORIG_TOKEN=$(echo "$API_RESPONSE" | jq -r '.baseline.token')

MITM_PORT=$((30000 + $(echo "$DEV_ID" | cksum | cut -d' ' -f1) % 500))
FRIDA_PORT=$((MITM_PORT + 10000))
ALIAS="$DEV_ID"

export NMAP_ORIG_SSAID="$ORIG_SSAID"
export NMAP_ORIG_ADID="$ORIG_ADID"
export NMAP_ORIG_IDFV="$ORIG_IDFV"
export NMAP_ORIG_NI="$ORIG_NI"
export NMAP_ORIG_TOKEN="$ORIG_TOKEN"
export NMAP_SPOOFED_SSAID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 16 | head -n 1)
export NMAP_SPOOFED_ADID=$(cat /proc/sys/kernel/random/uuid)
export NMAP_SPOOFED_IDFV=$(cat /proc/sys/kernel/random/uuid)
export NMAP_SPOOFED_NI=$(echo -n "$NMAP_SPOOFED_SSAID" | md5sum | awk '{print $1}')
export NMAP_SPOOFED_NLOG_TOKEN=$(python3 -c "import string, random; print(''.join(random.choices(string.ascii_letters + string.digits, k=16)))")

# [2] Setup Logging
DATE_STR=$(date +%Y%m%d)
TIME_STR=$(date +%H%M%S)
LOG_DIR="logs/${DEV_ID}/${DATE_STR}/${TIME_STR}-auto-${TASK_ID}"
mkdir -p "$LOG_DIR"
export CAPTURE_LOG_DIR="$(realpath "$LOG_DIR")"

# [3] Preparation
echo -e "${CYAN}[$ALIAS]${NC} Preparing device..."
adb -s "$DEV_ID" shell am force-stop $PKG_NAME
adb -s "$DEV_ID" shell am force-stop $GPS_PKG
adb -s "$DEV_ID" shell settings put global http_proxy :0 2>/dev/null
pkill -f "mitmdump.*$MITM_PORT" 2>/dev/null

# IP & Data Purge
adb -s "$DEV_ID" shell su -c "cmd connectivity airplane-mode enable"
sleep 1
adb -s "$DEV_ID" shell su -c "cmd connectivity airplane-mode disable"
adb -s "$DEV_ID" shell su -c "find /data/data/$PKG_NAME -mindepth 1 -maxdepth 1 ! -name 'lib' -exec rm -rf {} +"
sleep 3

# [4] Proxy & GPS
adb -s "$DEV_ID" reverse tcp:"$MITM_PORT" tcp:"$MITM_PORT" >/dev/null 2>&1
adb -s "$DEV_ID" shell settings put global http_proxy localhost:"$MITM_PORT"
PYTHONWARNINGS=ignore nohup mitmdump -p "$MITM_PORT" -s lib/mitm_addon.py --ssl-insecure --listen-host 0.0.0.0 --set flow_detail=0 > "$CAPTURE_LOG_DIR/mitm.log" 2>&1 &
MITM_PID=$!

"$BASE_DIR/gps/static.sh" "$DEV_ID" "$TARGET_LAT" "$TARGET_LNG" "$TASK_ID"

# [5] Frida & Monitor
adb -s "$DEV_ID" shell "su -c 'killall -9 frida-server 2>/dev/null'"
adb -s "$DEV_ID" shell "su -c '/data/local/tmp/frida-server -D >/dev/null 2>&1 &'"
sleep 2
adb -s "$DEV_ID" forward tcp:$FRIDA_PORT tcp:27042 >/dev/null 2>&1
nohup frida -H 127.0.0.1:$FRIDA_PORT --runtime=v8 -f "$PKG_NAME" -l lib/hooks/survival_light.js -l lib/hooks/network_hook.js -l lib/hooks/data_collector.js -l lib/hooks/macro_agreement.js --no-auto-reload > "$CAPTURE_LOG_DIR/frida.log" 2>&1 &
FRIDA_PID=$!

# [IMPORTANT] Pass all task info to monitor.sh to avoid double API polling
./macro/monitor.sh "$DEV_ID" "$CAPTURE_LOG_DIR" "$TASK_ID" "$TARGET_NAME" "$TARGET_ADDRESS" &
AUTO_PID=$!

# [6] Start App
(sleep 2; adb -s "$DEV_ID" shell monkey -p "$PKG_NAME" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1) &

cleanup() {
    echo -e "\n${YELLOW}[$ALIAS] Cleaning up processes...${NC}"
    kill -9 $MITM_PID $FRIDA_PID $AUTO_PID 2>/dev/null
    adb -s "$DEV_ID" shell am force-stop $PKG_NAME
    adb -s "$DEV_ID" shell am force-stop $GPS_PKG
    adb -s "$DEV_ID" shell settings put global http_proxy :0 2>/dev/null
    exit 0
}
trap cleanup INT TERM

# [7] Completion Monitor (Wait for Start, then Watch)
echo -e "${YELLOW}[$ALIAS] Waiting for app startup...${NC}"
MAX_WAIT=30
for ((i=0; i<MAX_WAIT; i++)); do
    # More robust PID check using dumpsys or su
    PID=$(adb -s "$DEV_ID" shell su -c "pidof $PKG_NAME" | tr -d '\r\n')
    if [ -n "$PID" ]; then
        echo -e "${GREEN}[$ALIAS] App is running (PID: $PID). Monitor active.${NC}"
        break
    fi
    sleep 1
done

if [ -z "$PID" ]; then
    echo -e "${RED}[!] App failed to start. Terminating...${NC}"
    cleanup
fi

while true; do
    PID=$(adb -s "$DEV_ID" shell su -c "pidof $PKG_NAME" | tr -d '\r\n')
    if [ -z "$PID" ]; then
        echo -e "${MAGENTA}[$ALIAS] App closed. Session Finished.${NC}"
        cleanup
    fi
    # Optional: Focus check could be here, but PID loss is the safest indicator for auto-finish
    sleep 10
done
