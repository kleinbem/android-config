set working-directory := "."

default:
    @just --list

# ==============================================================================
# Fleet Overview & Configuration
# ==============================================================================

# Show fleet status across all connected devices (battery, Shizuku, NetBird, foreground)
[group("Fleet")]
status:
    @python3 scripts/status.py

# Apply declarative tuning (animations, 120Hz, DNS, keyboard, doze whitelist, debloat)
[group("Fleet")]
tune device="all":
    @python3 scripts/apply-device.py {{quote(device)}}

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
    # The profile's device, over USB (serial) or wireless ADB (ip:5555); a
    # name without a profile is taken as a serial. Profile errors stay visible.
    if [ -f "devices/$DEV.yaml" ]; then
        read -r USB_SERIAL IP < <(python3 -c "import sys, yaml; c = yaml.safe_load(open(sys.argv[1])) or {}; print(c.get('serial') or '-', c.get('ip') or '-')" "devices/$DEV.yaml")
    else
        USB_SERIAL=$DEV IP=-
    fi
    CONNECTED=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }' || true)
    SERIAL=""
    for s in "$USB_SERIAL" "$IP:5555"; do
        if grep -qxF -- "$s" <<<"$CONNECTED"; then SERIAL="$s"; break; fi
    done
    if [ -z "$SERIAL" ]; then
        echo "❌ $DEV ($USB_SERIAL) is not connected over ADB."
        exit 1
    fi
    # Pinned fleet host keys from nix-config's INFRASTRUCTURE.yaml (the
    # workspace root's symlink, found from a primary checkout or a .ws one).
    INFRA="${INFRA_YAML:-}"
    if [ -z "$INFRA" ]; then
        for d in .. ../..; do
            if [ -e "$d/INFRASTRUCTURE.yaml" ]; then INFRA="$d/INFRASTRUCTURE.yaml"; break; fi
        done
    fi
    if [ -z "$INFRA" ]; then
        echo "❌ INFRASTRUCTURE.yaml not found; set INFRA_YAML=<path>."
        exit 1
    fi
    KNOWN_HOSTS="$(mktemp)"
    trap 'rm -f "$KNOWN_HOSTS"' EXIT
    python3 scripts/gen-known-hosts.py "$INFRA" "$KNOWN_HOSTS"
    echo "📱 Pushing Termux provisioning script to $SERIAL ($DEV)..."
    adb -s "$SERIAL" push scripts/provision-termux.sh /sdcard/Download/setup-termux.sh
    adb -s "$SERIAL" push "$KNOWN_HOSTS" /sdcard/Download/kleinbem_known_hosts
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

# ==============================================================================
# Migration & Data Management
# ==============================================================================

# Migrate media & WhatsApp directly between two devices
[group("Migration")]
migrate-media src="phone-old" dst="phone":
    @python3 scripts/migrate.py media --source {{quote(src)}} --target {{quote(dst)}}

# Pull WhatsApp, DCIM, and downloads into a local backup directory
[group("Migration")]
backup-media src="phone" out_dir="./backup":
    @python3 scripts/migrate.py backup-media --source {{quote(src)}} --out {{quote(out_dir)}}

# Restore local backup directory to target device
[group("Migration")]
restore-media in_dir="./backup" dst="phone":
    @python3 scripts/migrate.py restore-media --input {{quote(in_dir)}} --target {{quote(dst)}}

# Sideload/clone third-party apps from source to destination device
[group("Migration")]
clone-apps src="phone-old" dst="phone" filter="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(--source {{quote(src)}} --target {{quote(dst)}})
    filter={{quote(filter)}}
    if [ -n "$filter" ]; then
        args+=(--filter "$filter")
    fi
    python3 scripts/migrate.py clone-apps "${args[@]}"

# Trigger Android MediaScanner to index newly pushed photos & files
[group("Migration")]
media-scan target="phone":
    @python3 scripts/migrate.py scan --target {{quote(target)}}

# ==============================================================================
# Diagnostics & Remote Control
# ==============================================================================

# Interactive ADB shell into selected device
[group("Diagnostics")]
shell target="phone":
    #!/usr/bin/env bash
    SERIAL=$(python3 -c "import yaml, os; print(yaml.safe_load(open('devices/{{target}}.yaml'))['serial'])" 2>/dev/null || echo "{{target}}")
    adb -s "$SERIAL" shell

# Capture a high-res screenshot from device directly to host
[group("Diagnostics")]
screenshot target="phone" out_file="screenshot.png":
    #!/usr/bin/env bash
    SERIAL=$(python3 -c "import yaml, os; print(yaml.safe_load(open('devices/{{target}}.yaml'))['serial'])" 2>/dev/null || echo "{{target}}")
    echo "📸 Capturing screenshot from $SERIAL -> {{out_file}}..."
    adb -s "$SERIAL" exec-out screencap -p > "{{out_file}}"
    echo "✅ Saved to {{out_file}}"

# List third-party installed packages on device
[group("Diagnostics")]
list-apps target="phone":
    #!/usr/bin/env bash
    SERIAL=$(python3 -c "import yaml, os; print(yaml.safe_load(open('devices/{{target}}.yaml'))['serial'])" 2>/dev/null || echo "{{target}}")
    adb -s "$SERIAL" shell pm list packages -3 | sed 's/package://' | sort

# Enable ADB over TCP/IP and connect wirelessly
[group("Diagnostics")]
wifi-adb target="phone":
    #!/usr/bin/env bash
    set -euo pipefail
    SERIAL=$(python3 -c "import yaml, os; print(yaml.safe_load(open('devices/{{target}}.yaml'))['serial'])" 2>/dev/null || echo "{{target}}")
    IP=$(python3 -c "import yaml, os; print(yaml.safe_load(open('devices/{{target}}.yaml')).get('ip', ''))" 2>/dev/null || echo "")
    if [ -z "$IP" ]; then
        echo "❌ No IP address configured for {{target}}."
        exit 1
    fi
    echo "📶 Enabling ADB TCP/IP on $SERIAL (port 5555)..."
    adb -s "$SERIAL" tcpip 5555
    echo "🔌 Connecting to $IP:5555..."
    adb connect "$IP:5555"

# ==============================================================================
# Mirroring & Companion Workflows
# ==============================================================================

# Screen mirror via scrcpy (auto-detects USB or wireless)
[group("Mirror")]
[positional-arguments]
scrcpy target="phone" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="$1"
    shift
    # Serial and IP from devices/<target>.yaml; an unknown target is a serial.
    read -r SERIAL IP < <(python3 -c "import sys, yaml; c = yaml.safe_load(open(sys.argv[1])) or {}; print(c.get('serial', sys.argv[2]), c.get('ip') or '-')" "devices/$TARGET.yaml" "$TARGET" 2>/dev/null || echo "$TARGET -")
    [ "$IP" = "-" ] && IP=""
    case $TARGET in
        tablet) BITRATE="24M" ;;
        *) BITRATE="16M" ;;
    esac

    if adb devices | awk 'NR > 1 && $2 == "device" { print $1 }' | grep -qxF -- "$SERIAL"; then
        echo "🚀 Launching USB scrcpy for $TARGET ($BITRATE)..."
        scrcpy -s "$SERIAL" --max-fps 60 --video-bit-rate "$BITRATE" --stay-awake --power-off-on-close "$@"
    elif [ -n "$IP" ]; then
        echo "📡 Device not on USB. Connecting over WiFi ($IP)..."
        adb connect "$IP" 2>/dev/null || true
        scrcpy --tcpip="$IP" --max-fps 60 --video-bit-rate "$BITRATE" --stay-awake --power-off-on-close "$@"
    else
        echo "❌ Device $TARGET ($SERIAL) is not connected."
        exit 1
    fi

# Bring Huawei MatePad Pro into Desk Companion mode (Weylus canvas, DroidCam, aFreeRDP)
[group("Tablet")]
tablet-desk:
    #!/usr/bin/env bash
    set -euo pipefail
    SERIAL=$(python3 -c "import yaml; print(yaml.safe_load(open('devices/tablet.yaml'))['serial'])")
    echo "🖥️  Bringing MatePad Pro into Desk Companion mode..."
    adb -s "$SERIAL" forward tcp:4747 tcp:4747
    adb -s "$SERIAL" reverse tcp:1701 tcp:1701
    adb -s "$SERIAL" reverse tcp:3389 tcp:3389
    adb -s "$SERIAL" shell settings put global stay_on_while_plugged_in 7
    just start-shizuku || true
    echo "✅ Desk companion active!"
