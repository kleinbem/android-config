set working-directory := "."

default:
    @just --list

# Show fleet status across all connected devices (battery, Shizuku, NetBird, foreground)
[group("Fleet")]
status:
    @python3 scripts/status.py

# Apply declarative tuning (animations, 120Hz, DNS, keyboard, doze whitelist, debloat)
[group("Fleet")]
tune device="all":
    @python3 scripts/apply-device.py {{device}}

# Start Shizuku server daemon via ADB on all connected devices
[group("Fleet")]
start-shizuku:
    #!/usr/bin/env bash
    set -euo pipefail
    DEVS=$(adb devices | grep -v "List" | grep "device$" | cut -f1 || true)
    if [ -z "$DEVS" ]; then
        echo "❌ No authorized ADB devices found."
        exit 1
    fi
    for SERIAL in $DEVS; do
        MODEL=$(adb -s "$SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || echo "$SERIAL")
        echo "⚡ Checking Shizuku on $MODEL ($SERIAL)..."
        adb -s "$SERIAL" shell "
            APK_PATH=\$(pm path moe.shizuku.privileged.api 2>/dev/null | cut -d: -f2 | head -n 1)
            if [ -n \"\$APK_PATH\" ]; then
                if ps -ef | grep -q \"shizuku_server\"; then
                    echo \"✅ Shizuku already running on $MODEL.\"
                else
                    LIB_DIR=\"\$(dirname \"\$APK_PATH\")/lib/arm64\"
                    if [ -f \"\$LIB_DIR/libshizuku.so\" ]; then
                        \"\$LIB_DIR/libshizuku.so\"
                        echo \"✅ Shizuku started on $MODEL.\"
                    else
                        echo \"⚠️ libshizuku.so not found in \$LIB_DIR on $MODEL\"
                    fi
                fi
            else
                echo \"ℹ️ Shizuku is not installed on $MODEL.\"
            fi
        "
    done

# Provision Termux on connected phone or tablet (SSH keys, fleet aliases, herdr)
[group("Fleet")]
termux-provision device="phone":
    #!/usr/bin/env bash
    set -euo pipefail
    DEV="{{device}}"
    SERIAL=$(adb devices | grep -v "List" | grep "device$" | head -n 1 | cut -f1)
    if [ -z "$SERIAL" ]; then
        echo "❌ No ADB device found."
        exit 1
    fi
    echo "📱 Pushing Termux provisioning script to $SERIAL ($DEV)..."
    adb -s "$SERIAL" push scripts/provision-termux.sh /sdcard/Download/setup-termux.sh
    adb -s "$SERIAL" shell pm grant com.termux android.permission.READ_EXTERNAL_STORAGE 2>/dev/null || true
    adb -s "$SERIAL" shell cmd appops set com.termux MANAGE_EXTERNAL_STORAGE allow 2>/dev/null || true
    adb -s "$SERIAL" shell am start -n com.termux/.app.TermuxActivity >/dev/null 2>&1 || true
    sleep 2
    echo "⚡ Executing in Termux..."
    adb -s "$SERIAL" shell input text "bash\\ /sdcard/Download/setup-termux.sh\\ $DEV"
    adb -s "$SERIAL" shell input keyevent 66
    echo "⏳ Waiting for key generation..."
    sleep 6
    PUB="/sdcard/Download/${DEV}_termux.pub"
    if adb -s "$SERIAL" pull "$PUB" /tmp/${DEV}_termux.pub 2>/dev/null; then
        echo ""
        echo "🔑 Extracted $DEV public key:"
        cat "/tmp/${DEV}_termux.pub"
        echo ""
        echo "Add this key to nix-config/modules/nixos/keys.nix to authorize it."
    fi

# Screen mirror via scrcpy (auto-detects USB or wireless)
[group("Mirror")]
scrcpy target="phone" *args:
    #!/usr/bin/env bash
    set -e
    TARGET="{{target}}"
    case $TARGET in
        phone)
            SERIAL="R5CX31EERDT"
            IP="10.0.0.8"
            BITRATE="16M"
            ;;
        tablet)
            SERIAL="QBK6R20825000010"
            IP="10.0.0.215"
            BITRATE="24M"
            ;;
        dhirujaan)
            SERIAL="RFCT90BVPNE"
            IP="10.0.0.238"
            BITRATE="16M"
            ;;
        *)
            SERIAL="$TARGET"
            IP=""
            BITRATE="16M"
            ;;
    esac

    if adb devices | grep -q "$SERIAL"; then
        echo "🚀 Launching USB scrcpy for $TARGET ($BITRATE)..."
        scrcpy -s "$SERIAL" --max-fps 60 --video-bit-rate "$BITRATE" --stay-awake --power-off-on-close {{args}}
    elif [ -n "$IP" ]; then
        echo "📡 Device not on USB. Connecting over WiFi ($IP)..."
        adb connect "$IP" 2>/dev/null || true
        scrcpy --tcpip="$IP" --max-fps 60 --video-bit-rate "$BITRATE" --stay-awake --power-off-on-close {{args}}
    else
        echo "❌ Device $TARGET ($SERIAL) is not connected."
        exit 1
    fi

# Bring Huawei MatePad Pro into Desk Companion mode (Weylus canvas, DroidCam, aFreeRDP)
[group("Tablet")]
tablet-desk:
    #!/usr/bin/env bash
    set -euo pipefail
    SERIAL="QBK6R20825000010"
    echo "🖥️  Bringing MatePad Pro into Desk Companion mode..."
    adb -s "$SERIAL" forward tcp:4747 tcp:4747
    adb -s "$SERIAL" reverse tcp:1701 tcp:1701
    adb -s "$SERIAL" reverse tcp:3389 tcp:3389
    adb -s "$SERIAL" shell settings put global stay_on_while_plugged_in 7
    just start-shizuku || true
    echo "✅ Desk companion active!"
