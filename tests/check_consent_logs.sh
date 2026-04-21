#!/bin/bash
LOG_ROOT="/home/tech/nmap/test_nmap_v2/logs"
echo "Searching for sessions where 'ConsentRequestFragment' is missing or stalled..."
echo "--------------------------------------------------------"

# Find all session directories (excluding routes)
find "$LOG_ROOT" -maxdepth 3 -type d | grep "_T" | while read -r session_dir; do
    PACKET_LOG="$session_dir/all_packets.jsonl"
    if [ ! -f "$PACKET_LOG" ]; then continue; fi

    # Check if app launched
    LAUNCHED=$(grep -q "launch.app" "$PACKET_LOG" && echo "yes" || echo "no")
    if [ "$LAUNCHED" == "no" ]; then continue; fi

    # Check for Consent Screen
    CONSENT_SHOWN=$(grep -q "ConsentRequestFragment" "$PACKET_LOG" && echo "yes" || echo "no")
    # Check for Main Screen
    MAIN_SHOWN=$(grep -q "DiscoveryFragment" "$PACKET_LOG" && echo "yes" || echo "no")

    if [ "$CONSENT_SHOWN" == "no" ] && [ "$MAIN_SHOWN" == "no" ]; then
        echo -e "\e[1;31m[!] STALLED EARLY (No Consent, No Main):\e[0m $session_dir"
    elif [ "$CONSENT_SHOWN" == "no" ] && [ "$MAIN_SHOWN" == "yes" ]; then
        # This is expected if AGREE_MODE worked or user already agreed
        : 
    elif [ "$CONSENT_SHOWN" == "yes" ] && [ "$MAIN_SHOWN" == "no" ]; then
        echo -e "\e[1;33m[!] STALLED AT CONSENT:\e[0m $session_dir"
    fi
done
echo "--------------------------------------------------------"
echo "Done."
