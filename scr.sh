#!/usr/bin/env bash

# This script runs the scrcpy arrangement tool and automatically starts the Sync Controller.
# Pass --reset to restart all windows and the controller.

export DISPLAY="${DISPLAY:-:0}"
if [ -z "$XAUTHORITY" ]; then
    export XAUTHORITY="$HOME/.Xauthority"
fi

SCR_DIR="/home/tech/nmap/scrcpy"

# 1. 만약 --reset 옵션이 있다면 기존 동기화 컨트롤러도 종료합니다.
if [[ "$*" == *"--reset"* ]]; then
    echo "Reset: Closing existing Sync Controller..."
    pkill -f "sync_gui_control.py"
fi

# 2. 기기들을 그리드 형태로 배치합니다.
python3 "$SCR_DIR/arrange_scrcpy.py" "$@"

# 3. 동기화 컨트롤러가 실행 중이 아니라면 백그라운드에서 실행합니다.
if ! pgrep -f "sync_gui_control.py" > /dev/null; then
    echo "Starting Multi-Device Visual Sync Controller..."
    # GUI 환경이므로 백그라운드(&)로 실행하여 터미널을 점유하지 않게 합니다.
    python3 "$SCR_DIR/sync_gui_control.py" > /dev/null 2>&1 &
else
    echo "Sync Controller is already running."
fi
