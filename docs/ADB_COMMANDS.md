# Complete ADB Command Reference & Runbook

This document catalogues every low-level `adb` command used to migrate, configure, debloat, tune, and maintain Android devices across the Kleinbem fleet (Samsung Galaxy XCover 6 Pro, Huawei MatePad Pro, etc.).

---

## 1. Device Inspection & Diagnostics

### Identify Device & Build Information
```bash
# Query product model, OS version, and One UI build increment
adb -s <SERIAL> shell getprop ro.product.model
adb -s <SERIAL> shell getprop ro.build.version.release       # e.g. 16
adb -s <SERIAL> shell getprop ro.build.version.incremental   # e.g. G736BXXSCGZI2
adb -s <SERIAL> shell getprop ro.build.version.security_patch

# Check Anti-Rollback / Bootloader binary bit (SW REV)
# (Binary C = 12 on Samsung eFuse; prevents downgrade to Binary A = 10)
adb -s <SERIAL> shell getprop ro.boot.bootloader
```

### Power & Battery Diagnostics
```bash
# Detailed battery level, charging source, and temperature
adb -s <SERIAL> shell dumpsys battery

# Extract human-readable summary
adb -s <SERIAL> shell dumpsys battery | awk '
  /level:/ { print "Level:", $2 "%" }
  /temperature:/ { print "Temp:", $2/10 "°C" }
  /status:/ { print "Status:", ($2==5?"Full":($2==2?"Charging":"Discharging")) }
  /AC powered:/ { print "AC:", $2 }
  /USB powered:/ { print "USB:", $2 }
'
```

### Window & Display Diagnostics
```bash
# Check currently focused window and foreground application
adb -s <SERIAL> shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp'"

# Check display resolution, refresh rate, and density
adb -s <SERIAL> shell dumpsys display | grep -E 'mCurrentDisplayMode|mDefaultDisplayMode'
adb -s <SERIAL> shell wm size
adb -s <SERIAL> shell wm density
```

---

## 2. Display & Animation Tuning

### 0.5× Snappy Animations
```bash
# Speeds up UI transitions, window open/close, and animator durations by 2x
adb -s <SERIAL> shell settings put global window_animation_scale 0.5
adb -s <SERIAL> shell settings put global transition_animation_scale 0.5
adb -s <SERIAL> shell settings put global animator_duration_scale 0.5
```

### 120Hz Refresh Rate Lock (Samsung One UI)
```bash
# Lock peak and minimum refresh rates to 120Hz
adb -s <SERIAL> shell settings put system peak_refresh_rate 120.0
adb -s <SERIAL> shell settings put system min_refresh_rate 60.0   # or 120.0 for pure lock
```

### Keep Screen Awake While Plugged In
```bash
# 7 = AC (1) + USB (2) + Wireless (4)
adb -s <SERIAL> shell settings put global stay_on_while_plugged_in 7
```

---

## 3. Network & Zero-Trust Mesh

### System-Wide AdGuard Private DNS (DoT)
```bash
# Enable hostname-based Private DNS
adb -s <SERIAL> shell settings put global private_dns_mode hostname
adb -s <SERIAL> shell settings put global private_dns_specifier dns.adguard-dns.com

# Verify DNS configuration
adb -s <SERIAL> shell settings get global private_dns_mode
adb -s <SERIAL> shell settings get global private_dns_specifier
```

### NetBird Zero-Trust Mesh Inspection
```bash
# Check if NetBird VPN tunnel interface (tun1) is active
adb -s <SERIAL> shell ip -br addr show tun1 2>/dev/null || adb -s <SERIAL> shell ifconfig tun1

# Launch NetBird Client UI
adb -s <SERIAL> shell monkey -p io.netbird.client -c android.intent.category.LAUNCHER 1

# Test reachability to fleet mesh nodes (e.g. workstation nixos-nvme)
adb -s <SERIAL> shell ping -c 3 100.117.212.232
```

---

## 4. Input Method & Launcher Management

### Gboard Default Keyboard
```bash
# List all installed IMEs
adb -s <SERIAL> shell ime list -s -a

# Enable and set Gboard as default IME
adb -s <SERIAL> shell ime enable com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME
adb -s <SERIAL> shell ime set com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME

# Verify default input method
adb -s <SERIAL> shell settings get secure default_input_method
```

### Set Default Home Launcher (Lawnchair 14)
```bash
# Set Lawnchair as the default launcher (replaces Samsung One UI Home)
adb -s <SERIAL> shell cmd package set-home-activity app.lawnchair/.LawnchairLauncher

# Query current default home app
adb -s <SERIAL> shell cmd package resolve-activity --brief -c android.intent.category.HOME android.intent.action.MAIN
```

---

## 5. Battery Optimization (Doze Whitelisting)

Prevent background sync services and mesh daemons from being killed by Android Doze:
```bash
# Whitelist app package
adb -s <SERIAL> shell dumpsys deviceidle whitelist +<PACKAGE_NAME>

# Fleet standard whitelist set:
adb -s <SERIAL> shell dumpsys deviceidle whitelist +com.termux
adb -s <SERIAL> shell dumpsys deviceidle whitelist +io.netbird.client
adb -s <SERIAL> shell dumpsys deviceidle whitelist +io.heckel.ntfy
adb -s <SERIAL> shell dumpsys deviceidle whitelist +io.homeassistant.companion.android
adb -s <SERIAL> shell dumpsys deviceidle whitelist +com.github.catfriend1.syncthingandroid
adb -s <SERIAL> shell dumpsys deviceidle whitelist +app.lawnchair
adb -s <SERIAL> shell dumpsys deviceidle whitelist +moe.shizuku.privileged.api
adb -s <SERIAL> shell dumpsys deviceidle whitelist +com.looker.droidify
adb -s <SERIAL> shell dumpsys deviceidle whitelist +de.astubenbord.paperless_mobile

# View all currently whitelisted apps
adb -s <SERIAL> shell dumpsys deviceidle whitelist
```

---

## 6. Debloating & Telemetry Removal (User 0)

Disable bloatware and tracking apps safely without breaking system partitions:
```bash
# Disable package for primary user (User 0)
adb -s <SERIAL> shell pm disable-user --user 0 <PACKAGE_NAME>

# Fleet standard debloat set:
# Facebook services
adb -s <SERIAL> shell pm disable-user --user 0 com.facebook.katana
adb -s <SERIAL> shell pm disable-user --user 0 com.facebook.system
adb -s <SERIAL> shell pm disable-user --user 0 com.facebook.appmanager
adb -s <SERIAL> shell pm disable-user --user 0 com.facebook.services

# Samsung tracking / unwanted services
adb -s <SERIAL> shell pm disable-user --user 0 com.samsung.android.ipsgeofence
adb -s <SERIAL> shell pm disable-user --user 0 com.samsung.android.app.spage
adb -s <SERIAL> shell pm disable-user --user 0 com.samsung.android.bixby.agent
adb -s <SERIAL> shell pm disable-user --user 0 com.samsung.android.bixby.wakeup
adb -s <SERIAL> shell pm disable-user --user 0 com.samsung.android.kidsinstaller
adb -s <SERIAL> shell pm disable-user --user 0 com.samsung.android.aremoji
adb -s <SERIAL> shell pm disable-user --user 0 com.samsung.android.app.tips

# List all disabled packages
adb -s <SERIAL> shell pm list packages -d

# Re-enable a package if needed:
# adb -s <SERIAL> shell pm enable <PACKAGE_NAME>
```

---

## 7. AppOps & Storage Permissions (Android 16 / One UI 8.0)

Android 11–16 enforces Scoped Storage. Termux and file managers require elevated `MANAGE_EXTERNAL_STORAGE`:

```bash
# Grant standard runtime permissions
adb -s <SERIAL> shell pm grant com.termux android.permission.READ_EXTERNAL_STORAGE
adb -s <SERIAL> shell pm grant com.termux android.permission.WRITE_EXTERNAL_STORAGE

# Grant All Files Access via AppOps (bypasses Scoped Storage restrictions)
adb -s <SERIAL> shell cmd appops set com.termux MANAGE_EXTERNAL_STORAGE allow
adb -s <SERIAL> shell cmd appops set me.zhanghai.android.files MANAGE_EXTERNAL_STORAGE allow

# Grant system diagnostics permissions to DevCheck
adb -s <SERIAL> shell pm grant flar2.devcheck android.permission.BATTERY_STATS
adb -s <SERIAL> shell pm grant flar2.devcheck android.permission.DUMP
adb -s <SERIAL> shell pm grant flar2.devcheck android.permission.PACKAGE_USAGE_STATS
```

---

## 8. Elevated Shizuku Daemon Management

Start Shizuku server directly via ADB without requiring a reboot or wireless pairing:
```bash
# 1. Locate Shizuku APK path
APK_PATH=$(adb -s <SERIAL> shell pm path moe.shizuku.privileged.api | cut -d: -f2 | head -n 1)

# 2. Derive native 64-bit library directory
LIB_DIR=$(adb -s <SERIAL> shell dirname "$APK_PATH")/lib/arm64

# 3. Launch the Shizuku server executable
adb -s <SERIAL> shell "$LIB_DIR/libshizuku.so"

# 4. Verify running process
adb -s <SERIAL> shell ps -ef | grep shizuku_server
```

---

## 9. Data Migration & Backup Commands

### WhatsApp Chat Database & Media Migration
WhatsApp media and database live under `/sdcard/Android/media/com.whatsapp`.

```bash
# Pull entire WhatsApp directory from Old Device to workstation
adb -s <OLD_SERIAL> pull /sdcard/Android/media/com.whatsapp /tmp/whatsapp_backup

# Push WhatsApp directory to New Device
adb -s <NEW_SERIAL> shell mkdir -p /sdcard/Android/media
adb -s <NEW_SERIAL> push /tmp/whatsapp_backup /sdcard/Android/media/com.whatsapp
```

### Media & Camera Files
```bash
# Pull DCIM / Camera
adb -s <OLD_SERIAL> pull /sdcard/DCIM/Camera /tmp/phone_migration/DCIM/

# Push to New Device
adb -s <NEW_SERIAL> push /tmp/phone_migration/DCIM/Camera/. /sdcard/DCIM/Camera/

# Pull Downloads and Voice Recordings
adb -s <OLD_SERIAL> pull /sdcard/Download /tmp/phone_migration/
adb -s <OLD_SERIAL> pull /sdcard/Recordings /tmp/phone_migration/

# Trigger Android Media Scanner so files appear immediately in Gallery
adb -s <NEW_SERIAL> shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/DCIM/Camera"
```

### App APK Extraction & Sideloading
Clone an installed app from an old phone to a new phone when unavailable from Play Store:
```bash
# 1. Locate APK on source device
SRC_APK=$(adb -s <OLD_SERIAL> shell pm path <PACKAGE_NAME> | cut -d: -f2 | head -n 1)

# 2. Pull APK to workstation
adb -s <OLD_SERIAL> pull "$SRC_APK" /tmp/extracted_app.apk

# 3. Install on target device
adb -s <NEW_SERIAL> install -r /tmp/extracted_app.apk
```

---

## 10. Wireless ADB & Screen Mirroring

### Enable ADB over TCP/IP (Port 5555)
```bash
# While device is on USB, switch ADB daemon to TCP/IP mode
adb -s <SERIAL> tcpip 5555

# Disconnect USB, then connect over Wi-Fi
adb connect 10.0.0.8:5555

# Verify wireless connection
adb devices
```

### Low-Latency scrcpy Mirroring
```bash
# Fast USB mirror with 60 FPS, screen powered off on device, staying awake
scrcpy -s <SERIAL> --max-fps 60 --video-bit-rate 16M --stay-awake --power-off-on-close

# Wireless mirror
scrcpy --tcpip=10.0.0.8:5555 --max-fps 60 --video-bit-rate 16M --stay-awake
```

---

## 11. Desk Companion Port Forwards (Tablet Mode)

Reverse and forward ports for companion tools (Weylus drawing canvas, DroidCam webcam, RDP):
```bash
# DroidCam video stream (Tablet -> Workstation)
adb -s <SERIAL> forward tcp:4747 tcp:4747

# Weylus stylus drawing canvas (Workstation -> Tablet)
adb -s <SERIAL> reverse tcp:1701 tcp:1701

# aFreeRDP Remote Desktop (Workstation -> Tablet)
adb -s <SERIAL> reverse tcp:3389 tcp:3389
```

---

## 12. UI Automation & Screen Capture

```bash
# Capture screenshot directly to local machine
adb -s <SERIAL> exec-out screencap -p > screenshot.png

# Dump active UI hierarchy (inspect views, resource-ids, and texts)
adb -s <SERIAL> shell uiautomator dump /sdcard/window_dump.xml
adb -s <SERIAL> pull /sdcard/window_dump.xml /tmp/window_dump.xml

# Simulate touch events or key inputs
adb -s <SERIAL> shell input tap 540 1200
adb -s <SERIAL> shell input text "hello"
adb -s <SERIAL> shell input keyevent 66   # Enter
adb -s <SERIAL> shell input keyevent 3    # Home
adb -s <SERIAL> shell input keyevent 4    # Back
```
