#!/bin/bash
# test_nmap_v2/macro/monitor.sh: V18.2 Silent Background Monitor

DEV_ID=$1; LOG_DIR=$2; DEST_ID=$3
[ -z "$DEV_ID" ] || [ -z "$LOG_DIR" ] && exit 1

PKG_NAME="com.nhn.android.nmap"
ADB_KB_IME="com.android.adbkeyboard/.AdbIME"
GPS_PKG="com.rosteam.gpsemulator"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"; cd "$ROOT_DIR" || exit 1

export ABS_LOG_DIR=$(realpath "$LOG_DIR")
export CAPTURE_LOG_DIR="$ABS_LOG_DIR"
EXEC_LOG="$ABS_LOG_DIR/execution.log"
exec >> "$EXEC_LOG" 2>&1

MACRO_EXEC="python3 macro/macro_executor.py"
SCHEDULE_JSON="macro/action_schedule.json"

# --- [CORE] Functions ---
NOW() { date +"%H:%M:%S.%3N"; }
START_TS=$(date +%s)

declare -A STATE_FLAGS

stop_gps() {
    echo "[$(NOW)] [🛑] Stopping GPS Movement (Speed: 0.0m/s)"
    adb -s "$DEV_ID" shell su -c "am start-foreground-service -n $GPS_PKG/.servicex2484 -a ACTION_START_CONTINUOUS --ef velocidad 0.0" > /dev/null 2>&1
}

check_app_survival() {
    local ELAPSED=$(( $(date +%s) - START_TS ))
    if [ $ELAPSED -gt 30 ]; then
        if ! adb -s "$DEV_ID" shell pidof "$PKG_NAME" >/dev/null 2>&1; then
            echo "[$(NOW)] [!] App process dead. Stopping scheduler."; exit 1
        fi
    fi
}

human_random_sleep() {
    local sleep_sec=$(awk "BEGIN {srand(); print 1.0 + rand() * 2.0}")
    echo "[$(NOW)] [Delay] Humanizing for ${sleep_sec}s..."
    sleep "$sleep_sec"
}

type_destination_only() {
    if [ -z "$NMAP_DEST_NAME" ]; then
        echo "[$(NOW)] [!] ERROR: NMAP_DEST_NAME is empty. Skipping typing."
        return 1
    fi
    echo "[$(NOW)] [Action] Typing: $NMAP_DEST_NAME (via Python Helper)"
    python3 macro/type_helper.py "$DEV_ID" "$NMAP_DEST_NAME"
    echo "    > Waiting 4s for recommendation list..."; sleep 4
}

echo "[$(NOW)] [Scheduler:$DEV_ID] V18.2 Silent Mode Started."

# === Main Loop ===
while true; do
    check_app_survival
    
    # [V18.2] Heartbeat print REMOVED for log purity. 
    # Python (auto_reloader) provides unified status reports instead.

    if [[ "${STATE_FLAGS[STEP_08_DRIVING_GOAL]}" != "1" ]]; then
        if grep -q "routeend" "$ABS_LOG_DIR/events.log" 2>/dev/null; then
            echo "[$(NOW)] [🌟] CASE: routeend detected! Finalizing session."
            stop_gps 
            STATE_FLAGS[STEP_07_2_DRIVING_STARTED]=1
            STATE_FLAGS[STEP_08_DRIVING_GOAL]=1
            MATCHED_IDX="BYPASS"; ID="STEP_09_FINISH"
        fi
    fi

    PREV_STEP_DONE=true
    while read -r step; do
        [ -z "$step" ] && continue
        ID=$(echo "$step" | jq -r '.id')
        if [[ "${STATE_FLAGS[$ID]}" == "1" ]]; then PREV_STEP_DONE=true; continue; fi
        if [ "$PREV_STEP_DONE" = false ]; then break; fi
        if [ "$MATCHED_IDX" == "BYPASS" ] && [ "$ID" != "STEP_09_FINISH" ]; then continue; fi

        T_PAT=$(echo "$step" | jq -r '.type // empty' | tr -d '\r\n')
        N_PAT=$(echo "$step" | jq -r '.screen_name // empty' | tr -d '\r\n')
        U_PAT=$(echo "$step" | jq -r '.url // empty' | tr -d '\r\n')
        CAT=$(echo "$step" | jq -r '.category // "AutoV2"' | tr -d '\r\n')

        if [ "$MATCHED_IDX" != "BYPASS" ]; then
            MATCHED_IDX=""
            if [ -n "$T_PAT" ] && [ -n "$N_PAT" ]; then
                grep -F -q "[$T_PAT] $N_PAT" "$ABS_LOG_DIR/events.log" 2>/dev/null && MATCHED_IDX="events.log"
            elif [ -n "$U_PAT" ]; then
                grep -q "$U_PAT" "$ABS_LOG_DIR/events.log" 2>/dev/null && MATCHED_IDX="events.log"
            else
                MATCHED_IDX="IMMEDIATE"
            fi
        fi

        if [ -n "$MATCHED_IDX" ]; then
            [ "$MATCHED_IDX" != "IMMEDIATE" ] && [ "$MATCHED_IDX" != "BYPASS" ] && echo "[$(NOW)] [✓] Detected Step: $ID"

            ACTION=$(echo "$step" | jq -r '.action // empty' | tr -d '\r\n')
            if [ -n "$ACTION" ]; then
                if [ "$ACTION" == "TYPE_DESTINATION" ]; then type_destination_only
                elif [ "$ACTION" == "SELECT_ADDR_LIST" ]; then
                    echo "[$(NOW)] [Action] Selecting Address: $NMAP_DEST_ADDR"
                    $MACRO_EXEC "$DEV_ID" "text:$NMAP_DEST_ADDR" "$CAT"
                    if [ $? -ne 0 ]; then
                        curl -s -X POST "http://localhost:5003/api/v1/update_status" -H "Content-Type: application/json" \
                             -d "{\"log_id\": $NMAP_LOG_ID, \"status\": \"FAIL_ADDRESS_NOT_FOUND\", \"device_id\": \"$DEV_ID\"}" > /dev/null
                        adb -s "$DEV_ID" shell am force-stop "$PKG_NAME"; exit 1
                    fi
                elif [ "$ACTION" == "CLICK_ARRIVAL" ]; then
                    echo "[$(NOW)] [Action] Clicking '도착' (Arrival)..."
                    $MACRO_EXEC "$DEV_ID" "exact:도착" "$CAT"
                    [ $? -eq 0 ] && sleep 5 || break
                elif [ "$ACTION" == "CLICK_CAR_TAB" ]; then
                    $MACRO_EXEC "$DEV_ID" "id:com.nhn.android.nmap:id/tab_car" "$CAT"
                    [ $? -ne 0 ] && break
                elif [ "$ACTION" == "EXIT_SUCCESS" ]; then
                    echo "[$(NOW)] [Action] GOAL REACHED. EXTRACTING ACTUAL STATS..."
                    ACTUAL_DIST=0; ACTUAL_TIME=0
                    for f in $(ls -1v "$ABS_LOG_DIR"/*_trafficjam_log.json 2>/dev/null); do
                        DIST_VAL=$(jq -r '.request.body._decoded."1"."12" // 0' "$f" 2>/dev/null)
                        TIME_VAL=$(jq -r '.request.body._decoded."1"."13" // 0' "$f" 2>/dev/null)
                        if [ "$DIST_VAL" != "0" ] && [ "$TIME_VAL" != "0" ]; then
                            ACTUAL_DIST=$DIST_VAL; ACTUAL_TIME=$TIME_VAL
                            echo "    > Found Stats in $(basename "$f"): ${ACTUAL_DIST}m | ${ACTUAL_TIME}s"
                            break
                        fi
                    done
                    curl -s -X POST "http://localhost:5003/api/v1/update_status" -H "Content-Type: application/json" \
                         -d "{\"log_id\": $NMAP_LOG_ID, \"status\": \"SUCCESS\", \"device_id\": \"$DEV_ID\", \"drive_dist\": \"$ACTUAL_DIST\", \"drive_time\": \"$ACTUAL_TIME\"}" > /dev/null
                    SLEEP_SEC=$(( RANDOM % 11 + 20 ))
                    echo "[$(NOW)] [*] Waiting ${SLEEP_SEC}s for app to auto-return to home..."
                    sleep "$SLEEP_SEC"
                    adb -s "$DEV_ID" shell input keyevent 3
                    sleep 2; adb -s "$DEV_ID" shell am force-stop "$PKG_NAME"; exit 0
                else
                    [ "$ID" == "STEP_02_HOME" ] && human_random_sleep
                    echo "[$(NOW)] [Action] Executing: $ACTION"
                    $MACRO_EXEC "$DEV_ID" "$ACTION" "$CAT"
                    [ $? -ne 0 ] && break
                fi
            fi
            STATE_FLAGS[$ID]=1; PREV_STEP_DONE=true; continue 
        fi
        
        IS_REQUIRED=$(echo "$step" | jq -r '.control.required // true')
        if [ "$IS_REQUIRED" == "false" ]; then PREV_STEP_DONE=true; continue; fi
        PREV_STEP_DONE=false
    done < <(jq -c '.steps[]' "$SCHEDULE_JSON")

    sleep 2
done
