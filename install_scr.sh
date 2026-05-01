#!/usr/bin/env bash

# scrcpy-mask Installation & Execution Manual (V1.1)
# This script handles the deployment of the scrcpy-mask server and required libraries.

# ====================================================
# [Troubleshooting & Maintenance Manual]
# 1. Tkinter Black Screen Issue:
#    Tkinter GUI elements are NOT thread-safe. If the sync control window opens 
#    but stays black, ensure that UI updates (e.g., ImageTk.PhotoImage) are 
#    dispatched to the main thread using `root.after()`. Do not render in background threads.
# 2. Pillow (PIL) Compatibility:
#    Older Pillow versions lack `Image.Resampling`. To support any PC environment, 
#    use `getattr(Image, 'Resampling', Image).BILINEAR` instead of hardcoding it.
# ====================================================

MASK_DIR="/home/tech/nmap/scrcpy-mask"
SERVER_BIN="$MASK_DIR/assets/scrcpy-mask-server-v2.4"
WEB_DIR="$MASK_DIR/assets/web"

echo "===================================================="
echo "   scrcpy-mask Multi-Device Control Setup"
echo "===================================================="

# 0. Check & Install Required Python Libraries (Host side)
echo "[*] Checking Python dependencies..."

if ! command -v pip3 >/dev/null 2>&1; then
    echo "    > pip3 is missing. Attempting to install python3-pip..."
    sudo apt-get update && sudo apt-get install -y python3-pip
fi

if ! python3 -c "import tkinter" 2>/dev/null; then
    echo "    > tkinter is missing. Attempting to install python3-tk..."
    sudo apt-get update && sudo apt-get install -y python3-tk
else
    echo "    > tkinter is already installed."
fi

if ! python3 -c "import PIL.ImageTk" 2>/dev/null; then
    echo "    > Pillow or ImageTk is missing. Attempting to install required packages..."
    sudo apt-get install -y python3-pil.imagetk
    pip3 install --upgrade Pillow
else
    echo "    > Pillow and ImageTk are already installed."
fi

# 1. Check if server binary exists
if [ ! -f "$SERVER_BIN" ]; then
    echo "[!] Error: scrcpy-mask-server binary not found at $SERVER_BIN"
    exit 1
fi

# 2. Get connected devices
DEVICES=$(adb devices | grep -w "device" | awk '{print $1}')

if [ -z "$DEVICES" ]; then
    echo "[!] No devices connected via ADB."
    exit 1
fi

for serial in $DEVICES; do
    echo "----------------------------------------------------"
    echo "Setting up device: $serial"

    # Push server to device
    echo "[$serial] Pushing server to /data/local/tmp/scrcpy-mask-server.jar..."
    adb -s "$serial" push "$SERVER_BIN" /data/local/tmp/scrcpy-mask-server.jar
    
    # Setup Port Forwarding
    echo "[$serial] Setting up port reverse (tcp:8888)..."
    adb -s "$serial" reverse tcp:8888 tcp:8888 2>/dev/null || true
    
    echo "[$serial] Setup complete."
done

echo "----------------------------------------------------"
echo "Deployment Finished."
echo ""
echo "[Web Interface]"
echo "The web UI is located at: $WEB_DIR/index.html"
echo "You can open this file in your browser to start controlling devices."
echo ""
echo "[Execution Note]"
echo "To manually start the server on a device (if needed):"
echo "adb -s {SERIAL} shell CLASSPATH=/data/local/tmp/scrcpy-mask-server.jar app_process / scrcpy.mask.Server"
echo "===================================================="
