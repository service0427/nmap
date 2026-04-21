#!/bin/bash
# test_nmap_v2: Automated Fleet Daemon (Enhanced Observability)

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$BASE_DIR" || exit 1

GREEN="\e[1;32m"
CYAN="\e[1;36m"
YELLOW="\e[1;33m"
MAGENTA="\e[1;35m"
NC="\e[0m"

echo -e "${GREEN}[*] Naver Map Simulation Daemon Started.${NC}"
echo -e "${CYAN}[*] Interval: 10s | Execution Script: run.sh${NC}"

# Ensure logs directory exists
mkdir -p logs

while true; do
    echo -e "\n${CYAN}--- Fleet Status Check ($(date +"%H:%M:%S")) ---${NC}"
    
    DEVICE_LIST=$(adb devices | grep -v "List" | grep "device$" | awk '{print $1}')
    
    if [ -z "$DEVICE_LIST" ]; then
        echo -e "${YELLOW}[!] No devices connected via ADB.${NC}"
    else
        BUSY_COUNT=0
        IDLE_COUNT=0
        
        for SERIAL in $DEVICE_LIST; do
            # 해당 기기(SERIAL)로 이미 run.sh가 돌고 있는지 확인
            # pgrep -f "run.sh $SERIAL" 에서 "bash"를 포함하여 더 명확하게 체크
            if pgrep -f "run.sh $SERIAL" | grep -v "$$" > /dev/null; then
                echo -e "  [${MAGENTA}BUSY${NC}] Device $SERIAL is performing a task."
                ((BUSY_COUNT++))
            else
                echo -e "  [${GREEN}IDLE${NC}] Device $SERIAL is ready. Spawning new session..."
                # 백그라운드 실행 시 bash를 명시적으로 붙임
                nohup bash run.sh "$SERIAL" > "logs/${SERIAL}_live.log" 2>&1 &
                ((IDLE_COUNT++))
                sleep 2 # 간격 분산
            fi
        done
        echo -e "${CYAN}Summary: Total $(echo "$DEVICE_LIST" | wc -l) | ${MAGENTA}Busy $BUSY_COUNT${NC} | ${GREEN}Spawned $IDLE_COUNT${NC}"
    fi

    sleep 10
done
