#!/bin/bash
# test_nmap_v2: Smart Multi-Device Task Orchestrator (V2.9.2 - Port Hard Purge)

# Parse Arguments
SKIP_IP=false; SINGLE_DEV_ID=""
for arg in "$@"; do
    if [ "$arg" == "--no-ip" ]; then SKIP_IP=true; elif [[ "$arg" != --* ]]; then SINGLE_DEV_ID="$arg"; fi
done

PKG_NAME="com.nhn.android.nmap"

echo "============================================================"
echo "   NMAP V2 DYNAMIC TASK ORCHESTRATOR (V2.9.2)"
echo "   Action: Hard Purge & Socket Recovery"
echo "============================================================"

# 0. Initial Purge
pkill -9 -f "lib/main.sh"
pkill -9 -f "mitmdump"
pkill -9 -f "frida"
pkill -9 -f "monitor.sh"
sleep 2

# 0.5 Pre-Flight Setup (Environment Lock)
echo "============================================================"
echo "   Applying Pre-Flight Device Configurations..."
echo "============================================================"
bash /home/tech/nmap/cmd/portrait.sh > /dev/null 2>&1
bash /home/tech/nmap/cmd/mute.sh > /dev/null 2>&1
bash /home/tech/nmap/cmd/disable_mtp.sh > /dev/null 2>&1

get_devices() {
    if [ -n "$SINGLE_DEV_ID" ]; then echo "$SINGLE_DEV_ID"; else adb devices | grep -w "device" | awk '{print $1}'; fi
}

while true; do
    DEVICES=$(get_devices)
    [ -z "$DEVICES" ] && sleep 10 && continue

    echo -e "\n[*] [$(date +%H:%M:%S)] Scanning $(echo $DEVICES | wc -w) devices..."

    for DEV_ID in $DEVICES; do
        # 1. Surgical Process Check
        SCRIPT_PIDS=$(pgrep -f "[b]ash lib/main.sh $DEV_ID" | xargs)
        
        if [ -n "$SCRIPT_PIDS" ]; then
            LOCK_FILE="/tmp/nmap_lock_${DEV_ID}"
            if [ -f "$LOCK_FILE" ]; then
                AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE") ))
                if [ $AGE -lt 35 ]; then
                    echo -e "  - [$DEV_ID] Busy: Active (${AGE}s)"
                    continue
                fi
            fi
            echo -e "  - [$DEV_ID] STALE: Killing PIDs ($SCRIPT_PIDS)..."
            kill -9 $SCRIPT_PIDS 2>/dev/null
            rm -f "$LOCK_FILE"
        fi

        # 2. Device-side Foreground Lock
        CURRENT_FOCUS=$(adb -s "$DEV_ID" shell "dumpsys activity activities | grep -E 'mResumedActivity|mCurrentFocus|topResumedActivity' | grep $PKG_NAME" 2>/dev/null)
        if [ -n "$CURRENT_FOCUS" ]; then
            echo -e "  - [$DEV_ID] Busy: App in focus."
            continue
        fi

        # [NEW] Detect Sleep/Reboot state and Unlock
        WAKE_STATE=$(adb -s "$DEV_ID" shell dumpsys power 2>/dev/null | grep -o 'mWakefulness=[^ ]*' | head -n1)
        if [[ "$WAKE_STATE" != *"Awake"* ]]; then
            echo -e "  - [$DEV_ID] Sleep/Reboot Detected. Waking up..."
            adb -s "$DEV_ID" shell input keyevent 224 >/dev/null 2>&1
            sleep 1
        fi
        # Always attempt to dismiss keyguard (harmless if already unlocked)
        adb -s "$DEV_ID" shell wm dismiss-keyguard >/dev/null 2>&1

        # 3. Request Task
        echo -n "  - [$DEV_ID] Idle. Fetching..."
        API_URL="http://localhost:5003/api/v1/request?device_id=$DEV_ID"
        RESPONSE=$(curl -s "$API_URL")
        [ -z "$RESPONSE" ] || [ "$(echo "$RESPONSE" | jq -r '.status')" != "ok" ] && echo -e " No task." && continue

        # Extract
        LOG_ID=$(echo "$RESPONSE" | jq -r '.log_id')
        DEST_ID=$(echo "$RESPONSE" | jq -r '.destination.id')
        NAME=$(echo "$RESPONSE" | jq -r '.destination.name')
        FRIDA_PORT=$(echo "$RESPONSE" | jq -r '.port')
        MITM_PORT=$((FRIDA_PORT + 10000))
        
        echo -e " \e[1;32m[🚀] Task (LogID:$LOG_ID): $NAME\e[0m"

        # [NEW] Record Spoofed Identity to Server immediately after allocation
        SPOOFED_JSON=$(echo "$RESPONSE" | jq -c '.identity.spoofed')
        curl -s -X POST "http://localhost:5003/api/v1/update_status" \
             -H "Content-Type: application/json" \
             -d "{\"log_id\": $LOG_ID, \"status\": \"ALLOCATED\", \"device_id\": \"$DEV_ID\", \"spoofed_identity\": $SPOOFED_JSON}" > /dev/null

        # [CRITICAL] Hard Socket Purge (Use adb forward --remove instead of fuser to save scrcpy)
        adb -s "$DEV_ID" forward --remove tcp:$FRIDA_PORT >/dev/null 2>&1 || true
        fuser -k -n tcp "$MITM_PORT" >/dev/null 2>&1
        sleep 1

        # 4. EXECUTE V2 ENGINE
        NMAP_LOG_ID="$LOG_ID" \
        NMAP_DEST_ID="$DEST_ID" \
        NMAP_DEST_LAT=$(echo "$RESPONSE" | jq -r '.destination.lat') \
        NMAP_DEST_LNG=$(echo "$RESPONSE" | jq -r '.destination.lng') \
        NMAP_DEST_NAME="$NAME" \
        NMAP_DEST_ADDR=$(echo "$RESPONSE" | jq -r '.destination.address') \
        NMAP_MIN_ARRIVAL=$(echo "$RESPONSE" | jq -r '.destination.min_arrival // 10') \
        NMAP_MAX_ARRIVAL=$(echo "$RESPONSE" | jq -r '.destination.max_arrival // 30') \
        NMAP_MIN_SPEED=$(echo "$RESPONSE" | jq -r '.destination.min_speed // 40') \
        NMAP_MAX_SPEED=$(echo "$RESPONSE" | jq -r '.destination.max_speed // 80') \
        NMAP_ID_SSAID=$(echo "$RESPONSE" | jq -r '.identity.spoofed.ssaid') \
        NMAP_ID_ADID=$(echo "$RESPONSE" | jq -r '.identity.spoofed.adid') \
        NMAP_ID_IDFV=$(echo "$RESPONSE" | jq -r '.identity.spoofed.idfv') \
        NMAP_ID_NI=$(echo "$RESPONSE" | jq -r '.identity.spoofed.ni') \
        NMAP_ID_TOKEN=$(echo "$RESPONSE" | jq -r '.identity.spoofed.token') \
        NMAP_ORIG_SSAID=$(echo "$RESPONSE" | jq -r '.identity.original.ssaid') \
        NMAP_ORIG_ADID=$(echo "$RESPONSE" | jq -r '.identity.original.adid') \
        NMAP_ORIG_IDFV=$(echo "$RESPONSE" | jq -r '.identity.original.idfv') \
        NMAP_ORIG_NI=$(echo "$RESPONSE" | jq -r '.identity.original.ni') \
        NMAP_ORIG_TOKEN=$(echo "$RESPONSE" | jq -r '.identity.original.token') \
        NMAP_FRIDA_PORT="$FRIDA_PORT" \
        NMAP_NO_IP="$SKIP_IP" \
        setsid bash lib/main.sh "$DEV_ID" > /dev/null 2>&1 &
        disown %+ > /dev/null 2>&1 # [FIX] Detach job to suppress "Killed" messages
        
        sleep 1
    done
    sleep 15
done
