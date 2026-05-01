#!/usr/bin/env bash

# Base installation path
INSTALL_DIR="/home/tech/nmap/install"
CERT_PATH="$INSTALL_DIR/mitmproxy-ca-cert.crt"

# Define packages and their files
APPS=(
    "com.nhn.android.nmap:1:$INSTALL_DIR/map_6.5.2.1/base.apk $INSTALL_DIR/map_6.5.2.1/split_config.arm64_v8a.apk $INSTALL_DIR/map_6.5.2.1/split_config.xxhdpi.apk"
    "com.rosteam.gpsemulator:1:$INSTALL_DIR/gpsemulator/base.apk $INSTALL_DIR/gpsemulator/split_config.arm64_v8a.apk $INSTALL_DIR/gpsemulator/split_config.ko.apk $INSTALL_DIR/gpsemulator/split_config.xxhdpi.apk"
    "com.android.adbkeyboard:0:$INSTALL_DIR/ADBKeyboard.apk"
)

# Extract Certificate Hash
CERT_HASH=$(openssl x509 -inform PEM -subject_hash_old -in "$CERT_PATH" 2>/dev/null | head -1)

# Get all connected devices
DEVICES=$(adb devices | grep -w "device" | awk '{print $1}')

if [ -z "$DEVICES" ]; then
    echo "No devices connected."
    exit 1
fi

for serial in $DEVICES; do
    echo "--------------------------------------------------"
    echo "Checking device: $serial"
    
    # 1. App Installation with Pass Logic
    INSTALLED_PACKAGES=$(adb -s "$serial" shell pm list packages | cut -d':' -f2)
    for app in "${APPS[@]}"; do
        IFS=':' read -r pkg type files <<< "$app"
        if echo "$INSTALLED_PACKAGES" | grep -qx "$pkg"; then
            echo "[$serial] $pkg is already installed. Skipping."
        else
            echo "[$serial] $pkg not found. Installing..."
            if [ "$type" -eq "0" ]; then
                adb -s "$serial" install $files
            else
                adb -s "$serial" install-multiple $files
            fi
            [ $? -eq 0 ] && echo "[$serial] $pkg installed successfully." || echo "[$serial] Failed to install $pkg."
        fi
    done

    # 2. Magisk Modules Pass Logic
    echo "[$serial] Checking Magisk modules..."
    NEED_PUSH=false
    for f in "$INSTALL_DIR/Magisk_Module"/*.zip; do
        fname=$(basename "$f")
        if ! adb -s "$serial" shell "[ -f /sdcard/Download/$fname ]" >/dev/null 2>&1; then
            NEED_PUSH=true; break
        fi
    done
    if [ "$NEED_PUSH" = true ]; then
        echo "[$serial] Pushing Magisk modules to /sdcard/Download..."
        adb -s "$serial" push "$INSTALL_DIR/Magisk_Module/." /sdcard/Download/
    else
        echo "[$serial] Magisk modules already exist. Skipping."
    fi

    # 3. ROOT Certificate Injection (Critical for SSL)
    if [ -n "$CERT_HASH" ]; then
        echo "[$serial] Checking system certificate ($CERT_HASH.0)..."
        if adb -s "$serial" shell "su -c '[ -f /data/misc/user/0/cacerts-added/$CERT_HASH.0 ]'" >/dev/null 2>&1; then
            echo "[$serial] System certificate already injected. Skipping."
        else
            echo "[$serial] Injecting system certificate..."
            adb -s "$serial" push "$CERT_PATH" "/data/local/tmp/$CERT_HASH.0" >/dev/null 2>&1
            adb -s "$serial" shell "su -c '
                mkdir -p /data/misc/user/0/cacerts-added
                cp /data/local/tmp/$CERT_HASH.0 /data/misc/user/0/cacerts-added/$CERT_HASH.0
                chown system:system /data/misc/user/0/cacerts-added/$CERT_HASH.0
                chmod 644 /data/misc/user/0/cacerts-added/$CERT_HASH.0
                mount -o rw,remount / 2>/dev/null
                cp /data/local/tmp/$CERT_HASH.0 /system/etc/security/cacerts/$CERT_HASH.0
                chmod 644 /system/etc/security/cacerts/$CERT_HASH.0
                rm /data/local/tmp/$CERT_HASH.0
            '"
            echo "[$serial] Certificate injected. PLEASE REBOOT."
        fi
    fi

    # 4. System Tweak Pass Logic
    # WebView check
    WEBVIEW_STATUS=$(adb -s "$serial" shell pm list packages -d | grep com.google.android.webview)
    if [ -z "$WEBVIEW_STATUS" ]; then
        echo "[$serial] Downgrading/Disabling WebView..."
        adb -s "$serial" shell pm uninstall com.google.android.webview >/dev/null 2>&1
    fi

    # Play Store check
    PLAYSTORE_ENABLED=$(adb -s "$serial" shell pm list packages -e | grep com.android.vending)
    if [ -n "$PLAYSTORE_ENABLED" ]; then
        echo "[$serial] Disabling Google Play Store..."
        adb -s "$serial" shell pm disable-user --user 0 com.android.vending >/dev/null 2>&1
    fi

    # Auto-rotation
    adb -s "$serial" shell settings put system accelerometer_rotation 0 >/dev/null 2>&1
    
    # OTA updates
    adb -s "$serial" shell settings put global ota_disable_automatic_update 1 >/dev/null 2>&1
done

echo "--------------------------------------------------"
echo "Installation & Provisioning complete."
