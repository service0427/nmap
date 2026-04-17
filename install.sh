#!/usr/bin/env bash

# Base installation path
INSTALL_DIR="/home/tech/nmap/install"

# Define packages and their files
# Format: "package_name:install_type:files..."
# install_type: 0 for single apk, 1 for multiple split apks
APPS=(
    "com.nhn.android.nmap:1:$INSTALL_DIR/com.nhn.android.nmap_6.5.2.1/base.apk $INSTALL_DIR/com.nhn.android.nmap_6.5.2.1/split_config.arm64_v8a.apk $INSTALL_DIR/com.nhn.android.nmap_6.5.2.1/split_config.xxhdpi.apk"
    "com.rosteam.gpsemulator:1:$INSTALL_DIR/gpsemulator/base.apk $INSTALL_DIR/gpsemulator/split_config.arm64_v8a.apk $INSTALL_DIR/gpsemulator/split_config.ko.apk $INSTALL_DIR/gpsemulator/split_config.xxhdpi.apk"
    "com.android.adbkeyboard:0:$INSTALL_DIR/ADBKeyboard.apk"
)

# Get all connected devices
DEVICES=$(adb devices | grep -w "device" | awk '{print $1}')

if [ -z "$DEVICES" ]; then
    echo "No devices connected."
    exit 1
fi

for serial in $DEVICES; do
    echo "--------------------------------------------------"
    echo "Checking device: $serial"
    
    # Get the list of all installed packages once for efficiency
    INSTALLED_PACKAGES=$(adb -s "$serial" shell pm list packages | cut -d':' -f2)

    for app in "${APPS[@]}"; do
        IFS=':' read -r pkg type files <<< "$app"
        
        # Check if already installed
        if echo "$INSTALLED_PACKAGES" | grep -qx "$pkg"; then
            echo "[$serial] $pkg is already installed. Skipping."
        else
            echo "[$serial] $pkg not found. Installing..."
            if [ "$type" -eq "0" ]; then
                adb -s "$serial" install $files
            else
                adb -s "$serial" install-multiple $files
            fi
            
            if [ $? -eq 0 ]; then
                echo "[$serial] $pkg installed successfully."
            else
                echo "[$serial] Failed to install $pkg."
            fi
        fi
    done

    # Push Magisk modules to /sdcard/Download
    echo "[$serial] Pushing Magisk modules to /sdcard/Download..."
    adb -s "$serial" push "$INSTALL_DIR/Magisk_Module/." /sdcard/Download/
    if [ $? -eq 0 ]; then
        echo "[$serial] Magisk modules pushed successfully."
    else
        echo "[$serial] Failed to push Magisk modules."
    fi

    # Push and automatically install Certificates
    echo "[$serial] Checking for certificates in $INSTALL_DIR..."
    for cert in "$INSTALL_DIR"/*.{cer,crt,pem,der}; do
        if [ -f "$cert" ]; then
            filename=$(basename "$cert")
            echo "[$serial] Processing certificate: $filename"
            
            # 1. Push to Download just in case
            adb -s "$serial" push "$cert" /sdcard/Download/ >/dev/null 2>&1
            
            # 2. Extract Hash and install automatically via root
            cert_hash=$(openssl x509 -inform PEM -subject_hash_old -in "$cert" 2>/dev/null | head -1)
            
            if [ -n "$cert_hash" ]; then
                adb -s "$serial" push "$cert" "/data/local/tmp/$cert_hash.0" >/dev/null 2>&1
                adb -s "$serial" shell su -c "mkdir -p /data/misc/user/0/cacerts-added"
                adb -s "$serial" shell su -c "cp /data/local/tmp/$cert_hash.0 /data/misc/user/0/cacerts-added/$cert_hash.0"
                adb -s "$serial" shell su -c "chown system:system /data/misc/user/0/cacerts-added/$cert_hash.0"
                adb -s "$serial" shell su -c "chmod 644 /data/misc/user/0/cacerts-added/$cert_hash.0"
                adb -s "$serial" shell su -c "restorecon /data/misc/user/0/cacerts-added/$cert_hash.0 2>/dev/null || true"
                echo "[$serial] Certificate automatically installed ($cert_hash.0)."
            else
                echo "[$serial] Failed to parse certificate hash for $filename"
            fi
        fi
    done

    # [CRITICAL FIX] Android Chromium/WebView v120+ CA strict check bypass
    # 안드로이드 WebView가 PlayStore를 통해 최신버전으로 업데이트 된 경우, /system 인증서를 무시하고
    # /apex 엔진의 별도 인증서를 강제 참조하므로 Proxy가 중간자 공격으로 인식되어 통신(동의창 등)이 실패합니다.
    # 이 경우 네트워크 에러로 화면이 하얗게 멈추거나, 웹 글자비율이 기형적으로 왜곡(UI 200% 확대 버그)되는 현상이 발생합니다.
    # 이를 해결하기 위해 1) 업데이트를 강제로 삭제하여 공장 초기 버전(v111 등)으로 고정하고,
    # 2) 구글 플레이 스토어를 무력화하여 향후 와이파이 연결 시 몰래 자동 업데이트 되는 것을 영구 차단합니다.
    echo "[$serial] Downgrading Android System WebView to factory version to bypass APEX SSL strict checks..."
    adb -s "$serial" shell pm uninstall com.google.android.webview >/dev/null 2>&1
    
    echo "[$serial] Disabling Google Play Store to prevent future background auto-updates of WebView..."
    adb -s "$serial" shell pm disable-user --user 0 com.android.vending >/dev/null 2>&1

    # [설치 간편화] 자동 회전 끄기
    echo "[$serial] Turning off system auto-rotation natively..."
    adb -s "$serial" shell settings put system accelerometer_rotation 0 >/dev/null 2>&1

    # [안정성] 시스템/펌웨어 자동 업데이트 영구 차단 (삼성 OTA)
    echo "[$serial] Disabling System OTA Updates to prevent background firmare upgrades..."
    adb -s "$serial" shell settings put global ota_disable_automatic_update 1 >/dev/null 2>&1 || true
    adb -s "$serial" shell pm disable-user --user 0 com.wssyncmldm >/dev/null 2>&1 || true
    adb -s "$serial" shell pm disable-user --user 0 com.sec.android.soagent >/dev/null 2>&1 || true
    adb -s "$serial" shell pm disable-user --user 0 com.samsung.android.app.updatecenter >/dev/null 2>&1 || true
done

echo "--------------------------------------------------"
echo "Installation process complete."
