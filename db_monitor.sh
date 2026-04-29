#!/bin/bash
# Naver Map Auto-Simulation DB Monitor (V4.1) - Clean Text Only

DB_USER="nmap"
DB_PASS="Tech1324"
DB_NAME="nmap"

# 1. 헤더 출력
echo "========================================================================================================================"
echo "  NMAP Auto-Simulation Monitor | Today: $(date +%Y-%m-%d) | Update: $(date +%H:%M:%S)"
echo "========================================================================================================================"

# 2. 실시간 주행 기기 현황 (Active Fleet)
echo "[Active Fleet Status]"
ACTIVE_QUERY="SELECT device_id, LEFT(dest_name, 20) FROM task_log WHERE status = 'RUNNING' AND end_time IS NULL ORDER BY start_time DESC;"
ACTIVE_DEVS=$(mariadb -u$DB_USER -p$DB_PASS $DB_NAME -N -s -e "$ACTIVE_QUERY")

if [ -z "$ACTIVE_DEVS" ]; then
    echo "  > No active driving devices."
else
    echo "$ACTIVE_DEVS" | while read -r dev_id d_name; do
        echo "  > $dev_id is driving $d_name..."
    done
fi
echo ""

# 3. 통계 테이블 출력
printf "%-10s %-10s %-14s %-8s %-30s %s\n" "STATUS" "PROG" "LAST SUCCESS" "FAILS" "LAST FAIL REASON" "DESTINATION NAME"
echo "------------------------------------------------------------------------------------------------------------------------"

MAIN_QUERY="
SELECT 
    COALESCE(t.success_count, 0),
    d.daily_limit,
    IFNULL(DATE_FORMAT(t.last_success_at, '%H:%i:%s'), '-'),
    (SELECT COUNT(*) FROM fail_log f WHERE f.dest_id = d.dest_id AND DATE(f.created_at) = CURDATE()),
    IFNULL((SELECT fail_status FROM fail_log f WHERE f.dest_id = d.dest_id AND DATE(f.created_at) = CURDATE() ORDER BY created_at DESC LIMIT 1), '-'),
    d.name
FROM destinations d
LEFT JOIN daily_tasks t ON d.dest_id = t.dest_id AND t.work_date = CURDATE()
WHERE d.status = 'on'
ORDER BY t.last_success_at DESC, t.success_count DESC;
"

mariadb -u$DB_USER -p$DB_PASS $DB_NAME -N -s -e "$MAIN_QUERY" | while IFS=$'\t' read -r success limit last_success fails fail_reason name; do
    # 상태 판별 (순수 텍스트)
    if [ "$success" -ge "$limit" ]; then
        STATUS_STR="[DONE]"
    elif [ "$fails" -gt 0 ] && [ "$success" -eq 0 ]; then
        STATUS_STR="[ERR!]"
    else
        STATUS_STR="[RUN ]"
    fi

    # 정렬된 출력
    printf "%-10s %-10s %-14s %-8s %-30s %s\n" "$STATUS_STR" "$success/$limit" "$last_success" "$fails" "$fail_reason" "$name"
done

echo "========================================================================================================================"
