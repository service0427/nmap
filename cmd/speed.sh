#!/usr/bin/env bash

MIN_SPEED=$1
MAX_SPEED=$2

if [ -z "$MIN_SPEED" ] || [ -z "$MAX_SPEED" ]; then
    echo "Usage: ./cmd.sh --speed <MIN_KMH> <MAX_KMH>"
    echo "Example: ./cmd.sh --speed 10 20"
    exit 1
fi

echo "Dynamically adjusting GPS speed to $MIN_SPEED ~ $MAX_SPEED km/h for all active devices..."

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

for serial in $devices; do
    # Calculate a random speed in km/h between min and max
    TARGET_KMH=$(python3 -c "import random; print(round(random.uniform($MIN_SPEED, $MAX_SPEED), 1))")
    
    # GPS Emulator uses meters per second (m/s), so divide by 3.6
    TARGET_MPS=$(python3 -c "print(round($TARGET_KMH / 3.6, 6))")
    
    echo "[$serial] Adjusting GPS Speed to: ${TARGET_KMH} km/h (${TARGET_MPS} m/s)..."
    
    # Send ACTION_RESUME intent to update speed on the fly
    adb -s "$serial" shell su -c "am start-foreground-service -n com.rosteam.gpsemulator/.servicex2484 -a ACTION_RESUME --ef velocidad $TARGET_MPS --ei loopMode 0"
done

echo "GPS speed adjustment complete."
