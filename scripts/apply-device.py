#!/usr/bin/env python3
import sys, os, subprocess, yaml, glob

def get_connected_devices():
    out = subprocess.check_output(['adb', 'devices'], text=True)
    devs = {}
    for line in out.splitlines()[1:]:
        if '\tdevice' in line:
            parts = line.split()
            devs[parts[0]] = parts[1]
    return devs

def adb(serial, *args):
    cmd = ['adb', '-s', serial] + list(args)
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

def apply_device(profile_path, connected_serials):
    with open(profile_path, 'r') as f:
        cfg = yaml.safe_load(f)
    
    name = cfg.get('name', os.path.basename(profile_path).replace('.yaml', ''))
    serial = cfg.get('serial')
    
    if not serial or serial not in connected_serials:
        print(f"⚠️  Device '{name}' ({serial}) is NOT connected. Skipping.")
        return False

    print(f"\n==================================================")
    print(f"📱 Applying configuration to: {cfg.get('model', name)} [{serial}]")
    print(f"==================================================")

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
            res = adb(serial, 'shell', 'pm', 'disable-user', '--user', '0', pkg)
            # ignore output unless error

    # 7. Permissions
    perms = cfg.get('permissions', {})
    for pkg, p_list in perms.items():
        print(f"🔑 Granting {len(p_list)} permissions to {pkg}...")
        for p in p_list:
            adb(serial, 'shell', 'pm', 'grant', pkg, p)

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
    for p in profiles:
        if apply_device(p, connected):
            success_count += 1

    print(f"\n🎉 Finished applying configurations ({success_count} device(s) updated).")

if __name__ == '__main__':
    main()
