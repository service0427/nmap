#!/bin/bash
# utils/log_monitor.sh: Robust Polling Framework (V2 Automated)

DEV_ID=$1
LOG_DIR=$2
TARGET_ID=$3
# [NEW] Receive from run.sh arguments
TARGET_NAME=$4
TARGET_ADDRESS=$5

if [ -z "$DEV_ID" ] || [ -z "$LOG_DIR" ]; then
    echo "Usage: ./log_monitor.sh <DEVICE_ID> <LOG_DIR> <TASK_ID> <NAME> <ADDR>"
    exit 1
fi

PACKET_LOG="$LOG_DIR/all_packets.jsonl"
MACRO_EXEC="python3 macro/executor.py"
UI_CLICKER="python3 macro/ui_clicker.py"
LAST_LINE=0

# --- State Flags ---
APP_OPEN=false
CONSENT_DONE=false
CONSENT_CLICK_TIME=0
MAIN_LOADED=false
BANNER_DONE=false
BANNER_WAIT_START=0
SEARCH_CLICKED=false
SEARCH_ENTERED=false
CLICKER_STARTED=false
SUGGEST_CLICKED=false
POI_LOADED=false
DESTINATION_CLICKED=false
DESTINATION_CLICK_TIME=0
ROUTE_LIST_LOADED=false
CAR_TAB_CLICKED=false
CAR_ROUTE_LOADED=false
GUIDANCE_CLICKED=false
GUIDANCE_DONE=false
DRIVING_STARTED=false
DRIVING_START_TIME=0
CLOVA_TERMS_DONE=false
LAST_CAR_TAP_TIME=0
LAST_GUIDANCE_TAP_TIME=0
CAR_TAP_RETRY=0
GUIDANCE_TAP_RETRY=0

GREEN="\e[1;32m"
CYAN="\e[1;36m"
YELLOW="\e[1;33m"
RED="\e[1;31m"
NC="\e[0m"

NOW() { date +"[%H:%M:%S]"; }

echo -e "${CYAN}[Macro:$DEV_ID] Started. Task: $TARGET_NAME${NC}"

# Wait for log file
while [ ! -f "$PACKET_LOG" ]; do sleep 1; done

# === Main Loop ===
while true; do
    sleep 2
    CUR_TS=$(date +%s)
    if [ ! -f "$PACKET_LOG" ]; then continue; fi

    # --- [A] Time-based Fallback/Timeout Logic ---
    if [ "$MAIN_LOADED" = true ] && [ "$BANNER_DONE" = false ] && [ "$BANNER_WAIT_START" -ne 0 ]; then
        if [ $((CUR_TS - BANNER_WAIT_START)) -ge 8 ]; then
            echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] 배너 없음 확인. 검색 진행${NC}"
            BANNER_DONE=true
        fi
    fi

    if [ "$CAR_TAB_CLICKED" = true ] && [ "$CAR_ROUTE_LOADED" = false ]; then
        if [ $((CUR_TS - LAST_CAR_TAP_TIME)) -ge 12 ]; then
            echo -e "${YELLOW}$(NOW) [!] [$DEV_ID] 경로 로딩 지연 Fallback${NC}"
            CAR_ROUTE_LOADED=true
        fi
    fi

    # --- [B] Packet Processing ---
    TOTAL_LINES=$(wc -l < "$PACKET_LOG")
    if (( LAST_LINE < TOTAL_LINES )); then
        NEW_PACKETS=$(tail -n +$((LAST_LINE + 1)) "$PACKET_LOG" || true)
        NEW_NLOG=$(echo "$NEW_PACKETS" | grep "nlogapp" | grep -v "heartbeat" || true)
        LAST_LINE=$TOTAL_LINES

        if [ "$APP_OPEN" = false ] && echo "$NEW_NLOG" | grep -q "launch.app"; then
            echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] 앱 실행 확인${NC}"; APP_OPEN=true
        fi

        if [ "$APP_OPEN" = true ] && [ "$CONSENT_DONE" = false ]; then
            if echo "$NEW_NLOG" | grep -E -q '"ConsentRequestFragment"|"ConsentActivity"'; then
                if [ $((CUR_TS - CONSENT_CLICK_TIME)) -ge 5 ]; then
                    echo -e "${YELLOW}$(NOW) [!] [$DEV_ID] 약관 동의 시도${NC}"
                    $MACRO_EXEC "$DEV_ID" "agree_essential_service_1"; sleep 1; $MACRO_EXEC "$DEV_ID" "btn_final_confirm"
                    CONSENT_CLICK_TIME=$CUR_TS
                fi
            fi
            if echo "$NEW_NLOG" | grep -E -q '"DiscoveryFragment"|"MainFragment"'; then
                echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] 약관 통과${NC}"; CONSENT_DONE=true
            fi
        fi

        if [ "$CONSENT_DONE" = true ] && [ "$MAIN_LOADED" = false ]; then
            if echo "$NEW_NLOG" | grep -E -q '"MainFragment"|"DiscoveryFragment"'; then
                echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] 메인 진입${NC}"; MAIN_LOADED=true; BANNER_WAIT_START=$CUR_TS
            fi
        fi

        if [ "$MAIN_LOADED" = true ] && [ "$BANNER_DONE" = false ] && echo "$NEW_NLOG" | grep -q '"EventModalDialogFragment"'; then
            echo -e "${YELLOW}$(NOW) [!] [$DEV_ID] 배너 닫기${NC}"; adb -s "$DEV_ID" shell input keyevent BACK; BANNER_DONE=true
        fi

        if [ "$SEARCH_CLICKED" = true ] && [ "$SEARCH_ENTERED" = false ] && echo "$NEW_NLOG" | grep -q "SCH.all.entry"; then
            echo -e "${CYAN}$(NOW) [*] [$DEV_ID] 검색어 입력: $TARGET_NAME${NC}"
            DEFAULT_IME=$(adb -s "$DEV_ID" shell settings get secure default_input_method | tr -d '\r')
            adb -s "$DEV_ID" shell ime set com.android.adbkeyboard/.AdbIME; sleep 1
            for (( i=0; i<${#TARGET_NAME}; i++ )); do
                CHAR="${TARGET_NAME:$i:1}"
                if [ "$CHAR" = " " ]; then adb -s "$DEV_ID" shell input keyevent 62
                else adb -s "$DEV_ID" shell am broadcast -a ADB_INPUT_TEXT --es msg "$CHAR" >/dev/null 2>&1; fi
                sleep 0.2
            done
            adb -s "$DEV_ID" shell ime set "$DEFAULT_IME"
            SEARCH_ENTERED=true
        fi

        if [ "$SEARCH_ENTERED" = true ] && [ "$SUGGEST_CLICKED" = false ] && echo "$NEW_NLOG" | grep -q '"CK_suggest-place-list"'; then
            echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] 주소 선택${NC}"; SUGGEST_CLICKED=true
        fi

        if [ "$SUGGEST_CLICKED" = true ] && [ "$POI_LOADED" = false ] && echo "$NEW_NLOG" | grep -q '"poi.end"'; then
            echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] POI 로딩${NC}"; POI_LOADED=true
        fi

        if [ "$DESTINATION_CLICKED" = true ] && [ "$ROUTE_LIST_LOADED" = false ] && echo "$NEW_NLOG" | grep -E -q '"pubtrans.list"|"DRT.route.car"'; then
            echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] 경로 리스트${NC}"; ROUTE_LIST_LOADED=true
        fi

        if [ "$CAR_TAB_CLICKED" = true ] && [ "$CAR_ROUTE_LOADED" = false ]; then
            if echo "$NEW_NLOG" | grep -q '"PV_hipass-popup"'; then $MACRO_EXEC "$DEV_ID" "btn_hipass_yes"; fi
            if echo "$NEW_NLOG" | grep -E -q '"SW_route-cards"|"DRT.route.car"'; then
                echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] 자동차 경로${NC}"; CAR_ROUTE_LOADED=true
            fi
        fi

        if [ "$GUIDANCE_CLICKED" = true ] && [ "$GUIDANCE_DONE" = false ] && echo "$NEW_NLOG" | grep -E -q '"CK_navi-bttn"|"NaviDriveFragment"'; then
            echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] 안내시작 성공${NC}"; GUIDANCE_DONE=true; LAST_GUIDANCE_TAP_TIME=$CUR_TS
        fi

        if [ "$GUIDANCE_DONE" = true ] && [ "$DRIVING_STARTED" = false ]; then
            if echo "$NEW_NLOG" | grep -q '"BusinessHourWarningModalFragment"'; then $MACRO_EXEC "$DEV_ID" "btn_start_guidance_modal"; fi
            if echo "$NEW_NLOG" | grep -E -q '"NaviDriveFragment"|"NaviRouteGuidanceFragment"'; then
                echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] 주행 시작${NC}"; DRIVING_STARTED=true; DRIVING_START_TIME=$CUR_TS
            fi
        fi

        if [ "$DRIVING_STARTED" = true ]; then
            if [ "$CLOVA_TERMS_DONE" = false ] && echo "$NEW_NLOG" | grep -q '"ClovaGuestTermsActivity"'; then
                $MACRO_EXEC "$DEV_ID" "btn_clova_check"; sleep 2; $MACRO_EXEC "$DEV_ID" "btn_clova_agree"; CLOVA_TERMS_DONE=true
            fi
            if echo "$NEW_PACKETS" | grep -E -q 'routeend|v3/global/routeend'; then
                echo -e "${GREEN}$(NOW) [✓] [$DEV_ID] 도착 완료${NC}"; sleep 2; $MACRO_EXEC "$DEV_ID" "btn_end_guidance"
                adb -s "$DEV_ID" shell input keyevent 3; exit 0
            fi
        fi
    fi

    # --- [C] Step Execution ---
    if [ "$BANNER_DONE" = true ] && [ "$SEARCH_CLICKED" = false ]; then
        $MACRO_EXEC "$DEV_ID" "home_search_field"; SEARCH_CLICKED=true
    fi
    if [ "$SEARCH_ENTERED" = true ] && [ "$CLICKER_STARTED" = false ]; then
        $UI_CLICKER "$DEV_ID" "$TARGET_ADDRESS" &; CLICKER_STARTED=true
    fi
    if [ "$POI_LOADED" = true ] && [ "$DESTINATION_CLICKED" = false ]; then
        $UI_CLICKER "$DEV_ID" "exact:도착" &; DESTINATION_CLICKED=true; DESTINATION_CLICK_TIME=$CUR_TS
    fi
    if [ "$ROUTE_LIST_LOADED" = true ] && [ "$CAR_TAB_CLICKED" = false ]; then
        $UI_CLICKER "$DEV_ID" "id:com.nhn.android.nmap:id/tab_car"; LAST_CAR_TAP_TIME=$CUR_TS; CAR_TAB_CLICKED=true
    fi
    if [ "$CAR_ROUTE_LOADED" = true ] && [ "$GUIDANCE_DONE" = false ]; then
        if [ "$GUIDANCE_CLICKED" = false ]; then
            $MACRO_EXEC "$DEV_ID" "btn_start_guidance"; LAST_GUIDANCE_TAP_TIME=$CUR_TS; GUIDANCE_CLICKED=true
        elif [ $((CUR_TS - LAST_GUIDANCE_TAP_TIME)) -ge 8 ] && [ "$GUIDANCE_TAP_RETRY" -lt 8 ]; then
            $MACRO_EXEC "$DEV_ID" "btn_start_guidance"; LAST_GUIDANCE_TAP_TIME=$CUR_TS; ((GUIDANCE_TAP_RETRY++))
        fi
    fi
done
