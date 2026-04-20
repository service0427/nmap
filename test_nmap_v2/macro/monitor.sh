#!/bin/bash
# test_nmap_v2/macro/monitor.sh: V15.0 Aggressive Goal Detection & Stuck Recovery

DEV_ID=$1; LOG_DIR=$2; DEST_ID=$3
[ -z "$DEV_ID" ] || [ -z "$LOG_DIR" ] && exit 1

PKG_NAME="com.nhn.android.nmap"
ADB_KB_IME="com.android.adbkeyboard/.AdbIME"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"; cd "$ROOT_DIR" || exit 1

export ABS_LOG_DIR=$(realpath "$LOG_DIR")
export CAPTURE_LOG_DIR="$ABS_LOG_DIR"
EXEC_LOG="$ABS_LOG_DIR/execution.log"
exec >> "$EXEC_LOG" 2>&1

MACRO_EXEC="python3 macro/macro_executor.py"
SCHEDULE_JSON="macro/action_schedule.json"
NC="\e[0m"; RED="\e[1;31m"; GREEN="\e[1;32m"; YELLOW="\e[1;33m"; CYAN="\e[1;36m"; MAGENTA="\e[1;35m"

# --- [CORE] State Control (Stateless) ---
NOW() { date +"%H:%M:%S"; }
START_TS=$(date +%s)
# JSON에서 타임아웃 값 추출 (기본 1200초)
GLOBAL_TIMEOUT=$(jq -r '.config.global_timeout // 1200' "$SCHEDULE_JSON")
declare -A STATE_FLAGS

check_app_survival() {
    local ELAPSED=$(( $(date +%s) - START_TS ))
    
    # [V15.0] Strict 20-min Stuck Recovery
    if [ $ELAPSED -gt $GLOBAL_TIMEOUT ]; then 
        echo -e "${RED}[$(NOW)] [!!!] SESSION STUCK (>20 min). FORCING EXIT.${NC}"
        curl -s -X POST "http://localhost:5003/api/v1/update_status" -H "Content-Type: application/json" \
             -d "{\"log_id\": $NMAP_LOG_ID, \"status\": \"FAIL_TIMEOUT\", \"device_id\": \"$DEV_ID\"}" > /dev/null
        adb -s "$DEV_ID" shell am force-stop "$PKG_NAME"
        exit 1
    fi

    if [ $ELAPSED -gt 15 ]; then
        if ! adb -s "$DEV_ID" shell pidof "$PKG_NAME" >/dev/null 2>&1; then
            echo -e "${RED}[$(NOW)] [!] App process dead. Stopping scheduler.${NC}"; exit 1
        fi
    fi
}

human_random_sleep() {
    local sleep_sec=$(awk "BEGIN {srand(); print 1.0 + rand() * 2.0}")
    echo -e "${YELLOW}[$(NOW)] [Delay] Humanizing for ${sleep_sec}s...${NC}"
    sleep "$sleep_sec"
}

type_destination_only() {
    echo -e "${CYAN}[$(NOW)] [Action] Typing: $NMAP_DEST_NAME (via AdbIME)${NC}"
    local encoded=$(echo -n "$NMAP_DEST_NAME" | base64)
    adb -s "$DEV_ID" shell am broadcast -a ADB_INPUT_B64 --es msg "$encoded" >/dev/null 2>&1
    echo -e "    > Waiting 4s for recommendation list..."
    sleep 4
}

echo -e "${CYAN}[$(NOW)] [Scheduler:$DEV_ID] V15.0 Aggressive Goal Detection Mode.${NC}"

# === Main Loop ===
LAST_HEARTBEAT=0
while true; do
    check_app_survival
    
    CUR_TS=$(date +%s)
    if [ $(( CUR_TS - LAST_HEARTBEAT )) -gt 30 ]; then
        echo -e "${NC}[$(NOW)] [Heartbeat] Monitoring... (Elapsed: $(( CUR_TS - START_TS ))s)${NC}"
        LAST_HEARTBEAT=$CUR_TS
    fi

    # [V15.0] EMERGENCY BYPASS: If 'routeend' is anywhere in the log, jump to STEP_08 immediately
    if [[ "${STATE_FLAGS[STEP_08_DRIVING_GOAL]}" != "1" ]]; then
        if grep -q "routeend" "$ABS_LOG_DIR/events.log" 2>/dev/null; then
            echo -e "${MAGENTA}[$(NOW)] [🌟] EMERGENCY BYPASS: 'routeend' detected in log! Jumping to goal.${NC}"
            
            # Execute STEP_08 Action
            echo -e "${CYAN}[$(NOW)] [Action] Clicking '안내종료' (Emergency Path)...${NC}"
            $MACRO_EXEC "$DEV_ID" "exact:안내종료" "01.SearchAndNavi"
            
            # Mark critical steps as done
            STATE_FLAGS[STEP_07_2_DRIVING_STARTED]=1
            STATE_FLAGS[STEP_08_DRIVING_GOAL]=1
            # Continue loop to hit STEP_09_FINISH in next cycle
        fi
    fi

    # Sequential Workflow Progression
    PREV_STEP_DONE=true
    while read -r step; do
        [ -z "$step" ] && continue
        ID=$(echo "$step" | jq -r '.id')
        
        if [[ "${STATE_FLAGS[$ID]}" == "1" ]]; then 
            PREV_STEP_DONE=true; continue
        fi

        if [ "$PREV_STEP_DONE" = false ]; then break; fi

        T_PAT=$(echo "$step" | jq -r '.type // empty' | tr -d '\r\n')
        N_PAT=$(echo "$step" | jq -r '.screen_name // empty' | tr -d '\r\n')
        U_PAT=$(echo "$step" | jq -r '.url // empty' | tr -d '\r\n')
        CAT=$(echo "$step" | jq -r '.category // "AutoV2"' | tr -d '\r\n')

        MATCHED_IDX=""
        if [ -n "$T_PAT" ] && [ -n "$N_PAT" ]; then
            grep -F -q "[$T_PAT] $N_PAT" "$ABS_LOG_DIR/events.log" 2>/dev/null && MATCHED_IDX="events.log"
        elif [ -n "$U_PAT" ]; then
            grep -q "$U_PAT" "$ABS_LOG_DIR/events.log" 2>/dev/null && MATCHED_IDX="events.log"
        else
            MATCHED_IDX="IMMEDIATE"
        fi

        if [ -n "$MATCHED_IDX" ]; then
            [ "$MATCHED_IDX" != "IMMEDIATE" ] && echo -e "${GREEN}[$(NOW)] [✓] Detected Step: $ID${NC}"

            ACTION=$(echo "$step" | jq -r '.action // empty' | tr -d '\r\n')
            if [ -n "$ACTION" ]; then
                if [ "$ACTION" == "TYPE_DESTINATION" ]; then type_destination_only
                elif [ "$ACTION" == "SELECT_ADDR_LIST" ]; then
                    echo -e "${CYAN}[$(NOW)] [Action] Selecting Address: $NMAP_DEST_ADDR${NC}"
                    $MACRO_EXEC "$DEV_ID" "text:$NMAP_DEST_ADDR" "$CAT"
                    if [ $? -ne 0 ]; then
                        curl -s -X POST "http://localhost:5003/api/v1/update_status" -H "Content-Type: application/json" \
                             -d "{\"log_id\": $NMAP_LOG_ID, \"status\": \"FAIL_ADDRESS_NOT_FOUND\", \"device_id\": \"$DEV_ID\"}" > /dev/null
                        adb -s "$DEV_ID" shell am force-stop "$PKG_NAME"; exit 1
                    fi
                elif [ "$ACTION" == "CLICK_ARRIVAL" ]; then
                    echo -e "${CYAN}[$(NOW)] [Action] Clicking '도착' (Arrival)...${NC}"
                    $MACRO_EXEC "$DEV_ID" "exact:도착" "$CAT"
                    [ $? -eq 0 ] && sleep 5 || break
                elif [ "$ACTION" == "CLICK_CAR_TAB" ]; then
                    $MACRO_EXEC "$DEV_ID" "id:com.nhn.android.nmap:id/tab_car" "$CAT"
                    [ $? -ne 0 ] && break
                elif [ "$ACTION" == "EXIT_SUCCESS" ]; then
                    echo -e "${GREEN}[$(NOW)] [Action] GOAL REACHED. WAITING 15-30s BEFORE EXIT...${NC}"
                    
                    # [V15.1] Final Stats Extraction
                    TJ_FILE=$(ls -1v "$ABS_LOG_DIR"/*trafficjam_log*.json 2>/dev/null | tail -n 1)
                    DIST=0; DUR=0
                    if [ -n "$TJ_FILE" ]; then
                        TJ_DATA=$(jq -c '.request.body._decoded."1"' "$TJ_FILE" 2>/dev/null)
                        DIST=$(echo "$TJ_DATA" | jq -r '."12" // 0'); DUR=$(echo "$TJ_DATA" | jq -r '."13" // 0')
                    fi
                    
                    # Report Success Immediately
                    curl -s -X POST "http://localhost:5003/api/v1/update_status" -H "Content-Type: application/json" \
                         -d "{\"log_id\": $NMAP_LOG_ID, \"status\": \"SUCCESS\", \"device_id\": \"$DEV_ID\", \"drive_dist\": \"$DIST\", \"drive_time\": \"$DUR\"}" > /dev/null
                    
                    # Random Sleep 15~30s (User Request)
                    SLEEP_SEC=$(( RANDOM % 16 + 15 ))
                    echo -e "${CYAN}[$(NOW)] [*] Sleeping for ${SLEEP_SEC}s before closing app...${NC}"
                    sleep "$SLEEP_SEC"
                    
                    # Return to Home and Force Stop
                    adb -s "$DEV_ID" shell input keyevent 3
                    sleep 2; adb -s "$DEV_ID" shell am force-stop "$PKG_NAME"; exit 0
                else
                    [ "$ID" == "STEP_02_HOME" ] && human_random_sleep
                    echo -e "${CYAN}[$(NOW)] [Action] Executing: $ACTION${NC}"
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
