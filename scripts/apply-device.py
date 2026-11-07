#!/usr/bin/env python3
import sys
import os
import subprocess
import yaml
import glob

ADB_TIMEOUT = 60


def get_connected_devices():
    try:
        out = subprocess.check_output(['adb', 'devices'], text=True, timeout=ADB_TIMEOUT)
    except (OSError, subprocess.SubprocessError) as e:
        print(f"❌ Could not list ADB devices: {e}")
        sys.exit(1)
    devs = {}
    for line in out.splitlines()[1:]:
        if '\tdevice' in line:
            parts = line.split()
            devs[parts[0]] = parts[1]
    return devs

failures = []


def adb(serial, *args):
    """Run an adb command; record and print a failure instead of hiding it."""
    cmd = ['adb', '-s', serial] + list(args)
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=ADB_TIMEOUT)
    except (OSError, subprocess.SubprocessError) as e:
        failures.append(' '.join(args))
        print(f"   ❌ {' '.join(args)}: {e}")
        return ''
    if res.returncode != 0:
        failures.append(' '.join(args))
        detail = (res.stderr.strip() or res.stdout.strip()).splitlines()
        print(f"   ❌ {' '.join(args)}: {detail[-1] if detail else f'exit {res.returncode}'}")
    return res.stdout.strip()

def apply_device(profile_path, connected_serials):
    with open(profile_path, 'r') as f:
        cfg = yaml.safe_load(f)
    if not isinstance(cfg, dict):
        print(f"⚠️  Profile {profile_path} is empty or not a mapping. Skipping.")
        return False
    failures.clear()

    name = cfg.get('name', os.path.basename(profile_path).replace('.yaml', ''))
    serial = cfg.get('serial')
    
    if not serial or serial not in connected_serials:
        print(f"⚠️  Device '{name}' ({serial}) is NOT connected. Skipping.")
        return False

    print("\n==================================================")
    print(f"📱 Applying configuration to: {cfg.get('model', name)} [{serial}]")
    print("==================================================")

    # 1. Display & Animations
    display = cfg.get('display', {})
    anim = display.get('animations')
    if anim is not None:
        print(f"⚡ Setting animation scales to {anim}x...")
        adb(serial, 'shell', 'settings', 'put', 'global', 'window_animation_scale', str(anim))
        adb(serial, 'shell', 'settings', 'put', 'global', 'transition_animation_scale', str(anim))
        adb(serial, 'shell', 'settings', 'put', 'global', 'animator_duration_scale', str(anim))
    
    if 'peak_refresh_rate' in display:
        print(f"📺 Setting peak refresh rate to {display['peak_refresh_rate']}Hz...")
        adb(serial, 'shell', 'settings', 'put', 'system', 'peak_refresh_rate', str(display['peak_refresh_rate']))
    if 'min_refresh_rate' in display:
        adb(serial, 'shell', 'settings', 'put', 'system', 'min_refresh_rate', str(display['min_refresh_rate']))

    # 2. Private DNS
    dns = cfg.get('dns', {})
    if dns.get('mode') and dns.get('specifier'):
        print(f"🛡️  Enabling Private DNS ({dns['specifier']})...")
        adb(serial, 'shell', 'settings', 'put', 'global', 'private_dns_mode', dns['mode'])
        adb(serial, 'shell', 'settings', 'put', 'global', 'private_dns_specifier', dns['specifier'])

    # 3. Default Keyboard
    kb = cfg.get('keyboard', {}).get('default')
    if kb:
        print(f"⌨️  Setting default keyboard to {kb}...")
        adb(serial, 'shell', 'ime', 'enable', kb)
        adb(serial, 'shell', 'ime', 'set', kb)

    # 4. Default Launcher
    launcher = cfg.get('launcher', {}).get('activity')
    if launcher:
        print(f"🏠 Setting default launcher to {launcher}...")
        res = adb(serial, 'shell', 'cmd', 'package', 'set-home-activity', launcher)
        print(f"   Launcher status: {res or 'applied'}")

    # 5. Doze Whitelist
    doze = cfg.get('doze_whitelist', [])
    if doze:
        print(f"🔋 Whitelisting {len(doze)} apps from battery optimization...")
        for pkg in doze:
            adb(serial, 'shell', 'dumpsys', 'deviceidle', 'whitelist', f"+{pkg}")

    # 6. Debloat (Disable User 0)
    debloat = cfg.get('debloat', [])
    if debloat:
        print(f"🗑️  Debloating {len(debloat)} packages...")
        for pkg in debloat:
            adb(serial, 'shell', 'pm', 'disable-user', '--user', '0', pkg)

    # 7. Permissions
    perms = cfg.get('permissions', {})
    for pkg, p_list in perms.items():
        print(f"🔑 Granting {len(p_list)} permissions to {pkg}...")
        for p in p_list:
            adb(serial, 'shell', 'pm', 'grant', pkg, p)

    # 8. AppOps Permissions (Android 11-16 Scoped Storage)
    appops = cfg.get('appops', {})
    for pkg, ops in appops.items():
        print(f"🔒 Setting AppOps for {pkg}...")
        for op in ops:
            if isinstance(op, dict):
                for k, v in op.items():
                    adb(serial, 'shell', 'cmd', 'appops', 'set', pkg, k, str(v))
            elif isinstance(op, str):
                parts = op.replace(':', ' ').split()
                if len(parts) == 2:
                    adb(serial, 'shell', 'cmd', 'appops', 'set', pkg, parts[0], parts[1])

    # 9. Settings (global, secure, system)
    settings = cfg.get('settings', {})
    for namespace in ['global', 'secure', 'system']:
        ns_settings = settings.get(namespace, {})
        for key, val in ns_settings.items():
            print(f"⚙️  Setting {namespace}.{key} = {val}...")
            adb(serial, 'shell', 'settings', 'put', namespace, key, str(val))

    if failures:
        print(f"⚠️  {name}: {len(failures)} command(s) failed (see ❌ above).")
        return False
    print(f"✅ Configuration applied cleanly to {name}!")
    return True

def main():
    target = sys.argv[1] if len(sys.argv) > 1 else 'all'
    script_dir = os.path.dirname(os.path.abspath(__file__))
    devices_dir = os.path.join(os.path.dirname(script_dir), 'devices')
    
    connected = get_connected_devices()
    if not connected:
        print("❌ No ADB devices currently connected.")
        sys.exit(1)

    print(f"Connected ADB devices: {', '.join(connected.keys())}")

    if target == 'all':
        profiles = sorted(glob.glob(os.path.join(devices_dir, '*.yaml')))
    else:
        profile = os.path.join(devices_dir, f"{target}.yaml")
        if not os.path.exists(profile):
            print(f"❌ Device profile '{profile}' not found.")
            sys.exit(1)
        profiles = [profile]

    success_count = 0
    failed = []
    for p in profiles:
        if apply_device(p, connected):
            success_count += 1
        elif failures:
            failed.append(os.path.basename(p))

    print(f"\n🎉 Finished applying configurations ({success_count} device(s) updated cleanly).")
    if failed:
        print(f"❌ Failures on: {', '.join(failed)}")
        sys.exit(1)

if __name__ == '__main__':
    main()
