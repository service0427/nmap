#!/bin/bash
# test_nmap_v2: Fleet Real-time Dashboard

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$BASE_DIR" || exit 1

GREEN="\e[1;32m"
CYAN="\e[1;36m"
YELLOW="\e[1;33m"
MAGENTA="\e[1;35m"
NC="\e[0m"

while true; do
    clear
    echo -e "${CYAN}========================================================================${NC}"
    echo -e "   ${GREEN}NAVER MAP SIMULATION FLEET DASHBOARD${NC}   ($(date +"%H:%M:%S"))"
    echo -e "${CYAN}========================================================================${NC}"
    printf "%-16s | %-8s | %s\n" "DEVICE_ID" "STATE" "LAST_LOG_MESSAGE"
    echo "------------------------------------------------------------------------"

    DEVICE_LIST=$(adb devices | grep -v "List" | grep "device$" | awk '{print $1}')

    for SERIAL in $DEVICE_LIST; do
        STATE="${GREEN}IDLE${NC}"
        LAST_MSG="Waiting for task..."
        
        if pgrep -f "run.sh $SERIAL" > /dev/null; then
            STATE="${MAGENTA}BUSY${NC}"
            # live.log에서 마지막 한 줄 가져오기
            if [ -f "logs/${SERIAL}_live.log" ]; then
                LAST_MSG=$(tail -n 1 "logs/${SERIAL}_live.log" | sed 's/\x1B\[[0-9;]*[JKmsu]//g' | cut -c 1-80)
            fi
        fi

        printf "%-16s | %-16b | %s\n" "$SERIAL" "$STATE" "$LAST_MSG"
    done
    echo -e "${CYAN}========================================================================${NC}"
    echo " Press Ctrl+C to exit dashboard."
    sleep 3
done
