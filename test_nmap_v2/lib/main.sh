#!/bin/bash
# test_nmap_v2/lib/main.sh: Unified Task Execution Engine (V3.8 - Golden Template Injection)

LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$LIB_DIR/.." && pwd )"; cd "$ROOT_DIR" || exit 1

DEV_ID=$1
if [ -z "$DEV_ID" ]; then exit 1; fi

RESET_MODE=true; AGREE_MODE=true
PKG_NAME="com.nhn.android.nmap"; GPS_PKG="com.rosteam.gpsemulator"

if [ -z "$NMAP_LOG_ID" ] || [ -z "$NMAP_DEST_ID" ]; then exit 1; fi
NMAP_MITM_PORT=$((NMAP_FRIDA_PORT + 10000))

# Export Constraints for Python
export NMAP_MIN_ARRIVAL NMAP_MAX_ARRIVAL NMAP_MIN_SPEED NMAP_MAX_SPEED

CYAN="\e[1;36m"; GREEN="\e[1;32m"; YELLOW="\e[1;33m"; NC="\e[0m"; RED="\e[1;31m"

# 1. Setup Logs & Identity Print
DATE_STR=$(date +%Y%m%d); TIME_STR=$(date +%H%M%S)
LOG_REL_PATH="logs/${DEV_ID}/${DATE_STR}/${TIME_STR}_${NMAP_DEST_ID}"
mkdir -p "$LOG_REL_PATH"
export CAPTURE_LOG_DIR="$(cd "$LOG_REL_PATH" && pwd)"
EXEC_LOG="$CAPTURE_LOG_DIR/execution.log"
exec > >(tee -a "$EXEC_LOG") 2>&1

echo "============================================================"
echo " [$DEV_ID] TASK STARTED (LogID: $NMAP_LOG_ID)"
echo " Destination: $NMAP_DEST_NAME (ID: $NMAP_DEST_ID)"
echo " FRIDA:$NMAP_FRIDA_PORT | MITM:$NMAP_MITM_PORT"
echo "------------------------------------------------------------"
echo " [IDENTITY CONFIG]"
cat <<EOF | jq .
{
  "original": {
    "ssaid": "$NMAP_ORIG_SSAID",
    "adid":  "$NMAP_ORIG_ADID",
    "ni":    "$NMAP_ORIG_NI",
    "idfv":  "$NMAP_ORIG_IDFV",
    "token": "$NMAP_ORIG_TOKEN"
  },
  "spoofed": {
    "ssaid": "$NMAP_ID_SSAID",
    "adid":  "$NMAP_ID_ADID",
    "ni":    "$NMAP_ID_NI",
    "idfv":  "$NMAP_ID_IDFV",
    "token": "$NMAP_ID_TOKEN"
  }
}
EOF
echo "============================================================"

# 1.5 IP Change via Airplane Mode (V1 Logic)
if [ "$NMAP_NO_IP" != "true" ]; then
    echo -e "${YELLOW}[$DEV_ID] Toggling Airplane Mode to rotate IP...${NC}"
    adb -s "$DEV_ID" shell su -c "cmd connectivity airplane-mode enable"
    sleep 3
    adb -s "$DEV_ID" shell su -c "cmd connectivity airplane-mode disable"
    echo -n "    > Waiting for network connection..."
    for i in {1..15}; do
        if adb -s "$DEV_ID" shell "ping -c 1 -W 1 8.8.8.8" >/dev/null 2>&1; then
            echo -e " ${GREEN}[✓] Connected!${NC}"
            break
        fi
        sleep 1
    done
fi

# 2. Cleanup & IME Setup
adb -s "$DEV_ID" shell am force-stop $PKG_NAME
adb -s "$DEV_ID" shell am force-stop $GPS_PKG
adb -s "$DEV_ID" shell settings put global http_proxy :0 2>/dev/null
pkill -9 -f "mitmdump.*-p[[:space:]]+$NMAP_MITM_PORT" 2>/dev/null

ADB_KB_PKG="com.android.adbkeyboard"
adb -s "$DEV_ID" shell ime enable $ADB_KB_PKG/.AdbIME >/dev/null 2>&1
adb -s "$DEV_ID" shell ime set $ADB_KB_PKG/.AdbIME >/dev/null 2>&1

# 3. Golden Template Management (Backup -> Nuke -> Restore -> Refine)
if [ "$RESET_MODE" = true ]; then
    echo -e "    > [Step 1] Backing up existing environment..."
    adb -s "$DEV_ID" shell "su -c 'cp /data/data/$PKG_NAME/shared_prefs/ConsentInfo.xml /data/local/tmp/ConsentInfo_backup.xml'" 2>/dev/null

    echo -e "    > [Step 2] Performing Data Nuke..."
    adb -s "$DEV_ID" shell "su -c 'find /data/data/$PKG_NAME -mindepth 1 -maxdepth 1 ! -name \"lib\" -exec rm -rf {} +'"

    echo -e "    > [Step 3] Injecting Golden Template (Navi-Tab & Car-Mode)..."
    # Dynamic Date for Consent Realism
    RAND_DAYS=$(shuf -i 1-90 -n 1)
    TARGET_DATE=$(date -d "$RAND_DAYS days ago" +%Y-%m-%d)
    APP_UID=$(adb -s "$DEV_ID" shell "pm list packages -U $PKG_NAME" | grep -oE "uid:[0-9]+" | cut -d: -f2 | head -n 1)
    [ -z "$APP_UID" ] && APP_UID="root"

    # [ConsentInfo] - Full guest terms agreed
    cat <<EOF > tmp_consent_$DEV_ID.xml
<?xml version="1.0" encoding="utf-8"?><map><string name="PREF_CONSENT_GUEST_MAP_TERMS_AGREEMENT_STATUS">$TARGET_DATE</string><string name="PREF_CONSENT_GUEST_LOCATION_TERMS_AGREEMENT_STATUS">$TARGET_DATE</string><string name="PREF_CONSENT_GUEST_MAP_LOCATION_TERMS_AGREEMENT_STATUS">$TARGET_DATE</string><boolean name="PREF_CONSENT_CLOVA_CHECKED" value="true" /><boolean name="PREF_CONSENT_CLOVA_AGREED" value="true" /><boolean name="PREF_CONSENT_NEW_MAP_LOCATION_TERMS_AGREED" value="true" /></map>
EOF
    # [Preferences] - LAUNCHER_TAB_INDEX=1 (Navi Tab), PREF_ROUTE_TYPE=2 (Car Mode)
    cat <<EOF > tmp_prefs_$DEV_ID.xml
<?xml version="1.0" encoding="utf-8"?><map><boolean name="PREF_NOT_FIRST_RUN" value="true"/><boolean name="THEME_CHANGE_POPUP_NEVER_SHOW_AGAIN" value="true" /><int name="LAUNCHER_TAB_INDEX" value="1" /><boolean name="HIPASS_POPUP_SHOWN" value="true" /><int name="PREF_ROUTE_TYPE" value="2" /><int name="LAST_USED_MODE" value="1" /><boolean name="INTERNAL_NAVI_UUID_PERSONAL_ROUTE_TERMS_AGREED" value="true" /></map>
EOF
    # [NaviDefaults] - Car, Oil, and Auto-Route settings
    cat <<EOF > tmp_navi_$DEV_ID.xml
<?xml version="1.0" encoding="utf-8"?><map><boolean name="NaviUseHipassKey" value="true" /><int name="NaviCarTypeKey" value="1" /><int name="NaviOilTypeKey" value="1" /><boolean name="NaviGuideTrafficCamKey" value="false" /><boolean name="NaviAutoChangeRoute" value="true" /></map>
EOF

    adb -s "$DEV_ID" shell "su -c 'mkdir -p /data/data/$PKG_NAME/shared_prefs'"
    adb -s "$DEV_ID" push tmp_consent_$DEV_ID.xml /data/local/tmp/ConsentInfo.xml >/dev/null 2>&1
    adb -s "$DEV_ID" push tmp_prefs_$DEV_ID.xml /data/local/tmp/prefs.xml >/dev/null 2>&1
    adb -s "$DEV_ID" push tmp_navi_$DEV_ID.xml /data/local/tmp/navi.xml >/dev/null 2>&1
    
    adb -s "$DEV_ID" shell "su -c 'cp /data/local/tmp/ConsentInfo.xml /data/data/$PKG_NAME/shared_prefs/ && cp /data/local/tmp/prefs.xml /data/data/$PKG_NAME/shared_prefs/com.nhn.android.nmap_preferences.xml && cp /data/local/tmp/navi.xml /data/data/$PKG_NAME/shared_prefs/NativeNaviDefaults.xml && chown -R $APP_UID:$APP_UID /data/data/$PKG_NAME/shared_prefs && chmod -R 777 /data/data/$PKG_NAME/shared_prefs && restorecon -R /data/data/$PKG_NAME && setprop debug.nmap.ssaid $NMAP_ORIG_SSAID'"
    
    rm -f tmp_consent_$DEV_ID.xml tmp_prefs_$DEV_ID.xml tmp_navi_$DEV_ID.xml
    echo -e "    > ${GREEN}[✓] Environment Pre-Authorized & Optimized.${NC}"
fi

# 4. Networking & Proxy (V1 Standard)
echo -e "${CYAN}[$DEV_ID] Setting up Proxy Tunnel (MITM:$NMAP_MITM_PORT)...${NC}"
# Purge existing port usage to prevent binding errors
fuser -k -n tcp "$NMAP_FRIDA_PORT" >/dev/null 2>&1
fuser -k -n tcp "$NMAP_MITM_PORT" >/dev/null 2>&1

adb -s "$DEV_ID" reverse tcp:"$NMAP_FRIDA_PORT" tcp:"$NMAP_FRIDA_PORT" >/dev/null 2>&1
adb -s "$DEV_ID" reverse tcp:"$NMAP_MITM_PORT" tcp:"$NMAP_MITM_PORT" >/dev/null 2>&1
adb -s "$DEV_ID" shell settings put global http_proxy localhost:"$NMAP_MITM_PORT"
# Block QUIC (UDP 443) to force all HTTPS through MITM Proxy
adb -s "$DEV_ID" shell su -c 'iptables -I OUTPUT -p udp --dport 443 -j DROP' 2>/dev/null

# 5. Workers
# Export Environment for Python Helpers
export NMAP_LOG_ID NMAP_DEST_ID CAPTURE_LOG_DIR
export NMAP_MIN_ARRIVAL NMAP_MAX_ARRIVAL NMAP_MIN_SPEED NMAP_MAX_SPEED
export NMAP_ORIG_SSAID NMAP_ORIG_ADID NMAP_ORIG_NI NMAP_ORIG_IDFV NMAP_ORIG_TOKEN NMAP_ORIG_DOMAIN
export NMAP_ID_SSAID NMAP_ID_ADID NMAP_ID_NI NMAP_ID_IDFV NMAP_ID_TOKEN NMAP_ID_DOMAIN

nohup mitmdump -p "$NMAP_MITM_PORT" -s mitm/addon.py --ssl-insecure --listen-host 0.0.0.0 --set flow_detail=0 > "$CAPTURE_LOG_DIR/mitm.log" 2>&1 &
MITM_PID=$!
chmod +x macro/monitor.sh
nohup ./macro/monitor.sh "$DEV_ID" "$CAPTURE_LOG_DIR" "$NMAP_DEST_ID" &
MONITOR_PID=$!
setsid python3 gps/auto_reloader.py "$CAPTURE_LOG_DIR" "$DEV_ID" >> "$EXEC_LOG" 2>&1 &
RELOAD_PID=$!

# 6. Launch & Frida Survival (V1 Style Spawn)
echo -e "${GREEN}[$DEV_ID] Launching Optimized Session via Frida Spawn...${NC}"
FRIDA_LOG="$CAPTURE_LOG_DIR/frida.log"
# Force stop to ensure clean spawn
adb -s "$DEV_ID" shell am force-stop "$PKG_NAME"
adb -s "$DEV_ID" forward tcp:"$NMAP_FRIDA_PORT" tcp:27042 >/dev/null 2>&1

# Initialize Static GPS Position BEFORE app starts
./gps/static.sh "$DEV_ID" "$NMAP_DEST_LAT" "$NMAP_DEST_LNG"

# Spawn with V8 runtime for better survival
nohup frida -H localhost:"$NMAP_FRIDA_PORT" --runtime=v8 -f "$PKG_NAME" \
    -l lib/hooks/network_hook.js \
    -l lib/hooks/_core_survival.js \
    -l lib/hooks/macro_agreement.js \
    --no-auto-reload > "$FRIDA_LOG" 2>&1 &
FRIDA_PID=$!

LOCK_FILE="/tmp/nmap_lock_${DEV_ID}"
( while true; do touch "$LOCK_FILE"; sleep 10; done ) &
HEARTBEAT_PID=$!

# Wait for stabilization then ensure UI visibility
sleep 6
if ! adb -s "$DEV_ID" shell pidof "$PKG_NAME" >/dev/null 2>&1; then
    adb -s "$DEV_ID" shell monkey -p "$PKG_NAME" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
fi

cleanup() {
    echo -e "\n${YELLOW}[$DEV_ID] Cleaning up session...${NC}"
    
    # 1. Kill background workers strictly by PID (V1 Style)
    disown $MITM_PID $FRIDA_PID $MONITOR_PID $RELOAD_PID $HEARTBEAT_PID 2>/dev/null
    kill -9 $MITM_PID $FRIDA_PID $MONITOR_PID $RELOAD_PID $HEARTBEAT_PID 2>/dev/null
    
    # 2. Identity Integrity Audit (Leak Check)
    if [ -f "$CAPTURE_LOG_DIR/all_packets.jsonl" ]; then
        echo -e "${CYAN}    > Performing Identity Leak Audit...${NC}"
        for VAL in "$NMAP_ORIG_SSAID" "$NMAP_ORIG_ADID" "$NMAP_ORIG_IDFV" "$NMAP_ORIG_NI"; do
            if [ -n "$VAL" ] && [ ${#VAL} -gt 6 ]; then
                grep -q "\"request\":.*$VAL" "$CAPTURE_LOG_DIR/all_packets.jsonl" && \
                echo -e "${RED}[!] CRITICAL LEAK: Original value found in packets!${NC}"
            fi
        done
    fi

    # 3. Stop Android Components
    echo "    > Stopping App & GPS Emulator..."
    adb -s "$DEV_ID" shell am force-stop $PKG_NAME
    adb -s "$DEV_ID" shell "su -c 'am stopservice $GPS_PKG/.servicex2484'" 2>/dev/null
    adb -s "$DEV_ID" shell am force-stop $GPS_PKG
    
    # 4. Reset Networking (Surgical)
    adb -s "$DEV_ID" shell settings put global http_proxy :0 2>/dev/null
    adb -s "$DEV_ID" reverse --remove tcp:"$NMAP_FRIDA_PORT" 2>/dev/null
    adb -s "$DEV_ID" reverse --remove tcp:"$NMAP_MITM_PORT" 2>/dev/null
    adb -s "$DEV_ID" forward --remove tcp:"$NMAP_FRIDA_PORT" 2>/dev/null
    
    rm -f "$LOCK_FILE"
    echo -e "${GREEN}[$DEV_ID] Session terminated safely.${NC}"
    exit 0
}
trap cleanup INT TERM

# 7. Watchdog (Foreground & Process Check)
while true; do
    # 1. Process Integrity
    PID=$(adb -s "$DEV_ID" shell pidof "$PKG_NAME" 2>/dev/null)
    if [ -z "$PID" ]; then
        echo -e "${RED}[$DEV_ID] App process missing. Terminating...${NC}"
        cleanup
    fi

    # 2. Foreground Integrity (Check if app is actually visible)
    CURRENT_FOCUS=$(adb -s "$DEV_ID" shell "dumpsys activity activities | grep -E 'mResumedActivity|mCurrentFocus|topResumedActivity' | grep $PKG_NAME" 2>/dev/null)
    if [ -z "$CURRENT_FOCUS" ]; then
        echo -e "${YELLOW}[$DEV_ID] App moved to BACKGROUND. Terminating session cycle...${NC}"
        cleanup
    fi

    # 3. Frida Watchdog
    F_PID=$(pgrep -f "frida -H localhost:$NMAP_FRIDA_PORT")
    if [ -z "$F_PID" ]; then
        echo -e "${YELLOW}[$DEV_ID] Frida disconnected. Attempting hot-reconnect...${NC}"
        nohup frida -H localhost:"$NMAP_FRIDA_PORT" -n "$PKG_NAME" -l lib/hooks/network_hook.js -l lib/hooks/_core_survival.js -l lib/hooks/macro_agreement.js > "$FRIDA_LOG" 2>&1 &
        FRIDA_PID=$!
    fi

    sleep 5
done
