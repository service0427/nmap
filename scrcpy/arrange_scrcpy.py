#!/usr/bin/env python3
import subprocess
import argparse
import os
import sys
import time
import signal

# --- CONFIGURATION (Adjusted for slim smartphone ratio) ---
SCREEN_WIDTH = 3840
SCREEN_HEIGHT = 2160
TASKBAR_WIDTH = 100  # Left taskbar width

# Fixed Window Sizes (Slim Portrait)
WIN_WIDTH = 500     # Slimmer width for phone aspect ratio
WIN_HEIGHT = 1000   # Sufficient height for 4K half-screen

# Spacing between windows
X_GAP = 520         # Width + padding
Y_GAP = 1050        # Height + padding

COLUMNS = 5
ROWS = 2
MAX_DEVICES = COLUMNS * ROWS
# ---------------------

def get_connected_serials():
    """Returns a list of connected ADB serial numbers."""
    try:
        output = subprocess.check_output(["adb", "devices"]).decode("utf-8")
        lines = output.strip().split("\n")[1:]
        return [line.split()[0] for line in lines if line.strip() and "device" in line]
    except Exception as e:
        print(f"Error fetching devices: {e}")
        return []

def kill_scrcpy_for_serial(serial):
    """Kills existing scrcpy process for a specific serial."""
    try:
        output = subprocess.check_output(["pgrep", "-af", "scrcpy"]).decode("utf-8")
        for line in output.splitlines():
            if f"--serial {serial}" in line or f"-s {serial}" in line:
                pid = int(line.split()[0])
                print(f"[{serial}] Restarting existing process (PID: {pid})...")
                os.kill(pid, signal.SIGTERM)
                return True
    except (subprocess.CalledProcessError, ValueError, ProcessLookupError):
        pass
    return False

def main():
    parser = argparse.ArgumentParser(description="Arrange scrcpy windows in a slim 4x2 grid.")
    parser.add_argument("--reset", action="store_true", help="Close all existing scrcpy windows and restart.")
    args = parser.parse_args()

    if args.reset:
        print("Reset: Closing all scrcpy instances...")
        subprocess.run(["pkill", "scrcpy"], stderr=subprocess.DEVNULL)
        time.sleep(1)

    serials = get_connected_serials()
    if not serials:
        print("No devices found via ADB.")
        return

    print(f"Arranging {min(len(serials), MAX_DEVICES)} devices in a slim grid.")

    for i, serial in enumerate(serials[:MAX_DEVICES]):
        row = i // COLUMNS
        col = i % COLUMNS
        
        # Calculate position with fixed spacing
        x = TASKBAR_WIDTH + (col * X_GAP)
        y = row * Y_GAP

        if not args.reset:
            kill_scrcpy_for_serial(serial)

        print(f"[{serial}] Grid ({col},{row}) -> Pos: {x},{y} Size: {WIN_WIDTH}x{WIN_HEIGHT}")
        
        # Launch scrcpy with fixed slim dimensions
        cmd = [
            "scrcpy",
            "--serial", serial,
            "--window-x", str(int(x)),
            "--window-y", str(int(y)),
            "--window-width", str(WIN_WIDTH),
            "--window-height", str(WIN_HEIGHT),
            "--window-title", f"scrcpy-{serial}",
            "--window-borderless",
            "--always-on-top",
            "-m", "1024",
            "--max-fps", "30",
            "--stay-awake"
        ]
        
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.2)

if __name__ == "__main__":
    main()
