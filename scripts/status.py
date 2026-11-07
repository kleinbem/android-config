#!/usr/bin/env python3
import subprocess
import sys

ADB_TIMEOUT = 15


def get_devices():
    try:
        out = subprocess.check_output(['adb', 'devices'], text=True, timeout=ADB_TIMEOUT)
    except (OSError, subprocess.SubprocessError) as e:
        print(f"❌ Could not list ADB devices: {e}")
        sys.exit(1)
    devs = []
    for line in out.splitlines()[1:]:
        if '\tdevice' in line:
            devs.append(line.split()[0])
    return devs

timeouts = []


def adb(serial, *args):
    """Run an adb query; a timeout is recorded so the report can say so."""
    cmd = ['adb', '-s', serial] + list(args)
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=ADB_TIMEOUT)
    except subprocess.TimeoutExpired:
        timeouts.append((serial, ' '.join(args)))
        return ''
    return res.stdout.strip()

def oneui_suffix(raw):
    """' (One UI 6.1)' for ro.build.version.oneui=60100, '' if absent or odd."""
    try:
        v = int(raw)
        return f" (One UI {v // 10000}.{v // 100 % 100})"
    except ValueError:
        return ''


def main():
    devs = get_devices()
    if not devs:
        print("❌ No ADB devices currently connected.")
        return

    print("================================================================================")
    print("📱 Kleinbem Android Fleet Status")
    print("================================================================================")

    for s in devs:
        model = adb(s, 'shell', 'getprop', 'ro.product.model') or s
        android_v = adb(s, 'shell', 'getprop', 'ro.build.version.release')
        oneui_v = adb(s, 'shell', 'getprop', 'ro.build.version.oneui')
        
        # Battery
        batt_raw = adb(s, 'shell', 'dumpsys', 'battery')
        level, temp, ac, usb, status = "?", "?", "?", "?", "?"
        for line in batt_raw.splitlines():
            line = line.strip()
            if line.startswith('level:'):
                level = line.split(':')[1].strip() + "%"
            elif line.startswith('temperature:'):
                try:
                    temp = f"{float(line.split(':')[1].strip())/10:.1f}°C"
                except ValueError:
                    pass
            elif line.startswith('AC powered:'):
                ac = line.split(':')[1].strip()
            elif line.startswith('USB powered:'):
                usb = line.split(':')[1].strip()
            elif line.startswith('status:'):
                st_code = line.split(':')[1].strip()
                status = "Charging" if st_code == "2" else ("Full" if st_code == "5" else "Discharging")

        # Shizuku
        shizuku = "Running" if "shizuku_server" in adb(s, 'shell', 'ps -ef') else "Stopped"
        
        # NetBird IP
        netbird_ip = "Disconnected"
        ip_out = adb(s, 'shell', 'ip', '-br', 'a')
        for line in ip_out.splitlines():
            if 'tun' in line or 'wt' in line:
                parts = line.split()
                if len(parts) >= 3:
                    netbird_ip = parts[2]

        # Foreground Window
        fg_win = adb(s, 'shell', 'dumpsys', 'window')
        current_focus = "Unknown"
        for line in fg_win.splitlines():
            if 'mCurrentFocus' in line:
                current_focus = line.split('Window{')[-1].split('}')[0].strip()

        print(f"\n🔹 {model} [{s}]")
        print(f"   OS: Android {android_v}" + oneui_suffix(oneui_v))
        print(f"   Battery: {level} ({status}, {temp}, AC={ac}, USB={usb})")
        print(f"   NetBird: {netbird_ip}")
        print(f"   Shizuku: {shizuku}")
        print(f"   Active Window: {current_focus}")
        timed_out = [cmd for serial, cmd in timeouts if serial == s]
        if timed_out:
            print(f"   ⚠️  Timed out (values above may be wrong): {', '.join(timed_out)}")

    print("\n================================================================================")

if __name__ == '__main__':
    main()
    sys.exit(1 if timeouts else 0)
