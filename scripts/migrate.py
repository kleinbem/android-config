#!/usr/bin/env python3
"""
Fleet Data & App Migration Tool
Safely moves photos, WhatsApp media, downloads, and third-party apps between Android devices.
"""

import sys
import os
import argparse
import subprocess
import tempfile

MEDIA_PATHS = [
    ("WhatsApp Media & DB", "/sdcard/Android/media/com.whatsapp", "/sdcard/Android/media"),
    ("Camera Photos & Videos", "/sdcard/DCIM/Camera", "/sdcard/DCIM"),
    ("Pictures", "/sdcard/Pictures", "/sdcard"),
    ("Downloads", "/sdcard/Download", "/sdcard"),
    ("Voice Recordings", "/sdcard/Recordings", "/sdcard"),
]

def adb(serial, *args, check=True):
    cmd = ['adb', '-s', serial] + list(args)
    if check:
        return subprocess.check_output(cmd, text=True).strip()
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

def get_serial(target):
    # Check if target is a known profile name
    script_dir = os.path.dirname(os.path.abspath(__file__))
    profile_path = os.path.join(os.path.dirname(script_dir), 'devices', f"{target}.yaml")
    if os.path.exists(profile_path):
        import yaml
        with open(profile_path, 'r') as f:
            cfg = yaml.safe_load(f)
            return cfg.get('serial', target)
    return target

def scan_media(dst_serial):
    print(f"\n🔄 Triggering MediaScanner on {dst_serial}...")
    scan_paths = [
        "/sdcard/DCIM/Camera",
        "/sdcard/Pictures",
        "/sdcard/Download",
        "/sdcard/Recordings",
        "/sdcard/Android/media/com.whatsapp"
    ]
    for p in scan_paths:
        adb(dst_serial, 'shell', 'am', 'broadcast',
            '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
            '-d', f"file://{p}", check=False)
    print("✅ Media scan broadcast sent.")

def cmd_backup_media(args):
    src = get_serial(args.source)
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    print(f"📦 Backing up media from [{src}] to [{out_dir}]...")

    for label, remote_path, _ in MEDIA_PATHS:
        print(f"\n📥 Pulling {label} ({remote_path})...")
        res = subprocess.run(['adb', '-s', src, 'pull', remote_path, out_dir])
        if res.returncode == 0:
            print(f"✅ Successfully backed up {label}.")
        else:
            print(f"⚠️ Warning: Failed or partial transfer for {label}.")

    print(f"\n🎉 Backup complete in: {out_dir}")

def cmd_restore_media(args):
    dst = get_serial(args.target)
    in_dir = os.path.abspath(args.input)
    if not os.path.isdir(in_dir):
        print(f"❌ Backup directory does not exist: {in_dir}")
        sys.exit(1)

    print(f"📤 Restoring media from [{in_dir}] to [{dst}]...")
    for label, remote_path, parent_remote in MEDIA_PATHS:
        folder_name = os.path.basename(remote_path.rstrip('/'))
        local_src = os.path.join(in_dir, folder_name)
        if os.path.exists(local_src):
            print(f"\n🚀 Pushing {label} -> {parent_remote}/{folder_name}...")
            adb(dst, 'shell', 'mkdir', '-p', parent_remote, check=False)
            res = subprocess.run(['adb', '-s', dst, 'push', local_src, parent_remote])
            if res.returncode == 0:
                print(f"✅ Successfully restored {label}.")
            else:
                print(f"⚠️ Warning: Failed or partial transfer for {label}.")
        else:
            print(f"ℹ️ Skipping {label} (not found in backup folder).")

    scan_media(dst)
    print(f"\n🎉 Restore complete on device {dst}!")

def cmd_migrate_media(args):
    src = get_serial(args.source)
    dst = get_serial(args.target)
    temp_dir = tempfile.mkdtemp(prefix="android_migration_")
    print("🔄 Direct Device-to-Device Media Migration:")
    print(f"   Source:      {src}")
    print(f"   Destination: {dst}")
    print(f"   Buffer:      {temp_dir}")

    # 1. Pull from source
    args.out = temp_dir
    cmd_backup_media(args)

    # 2. Push to target
    args.input = temp_dir
    cmd_restore_media(args)

    print(f"\n🧹 Cleaning temporary buffer {temp_dir}...")
    subprocess.run(['rm', '-rf', temp_dir])
    print("✅ Direct migration finished cleanly!")

def cmd_clone_apps(args):
    src = get_serial(args.source)
    dst = get_serial(args.target)
    filter_pkg = args.filter

    print(f"📲 Cloning third-party apps from [{src}] -> [{dst}]...")
    raw = adb(src, 'shell', 'pm', 'list', 'packages', '-3')
    packages = [line.replace('package:', '').strip() for line in raw.splitlines() if line.strip()]

    if filter_pkg:
        packages = [p for p in packages if filter_pkg in p]

    print(f"Found {len(packages)} third-party package(s) on source.")
    temp_dir = tempfile.mkdtemp(prefix="android_apk_clone_")

    success, failed = 0, 0
    for i, pkg in enumerate(packages, 1):
        print(f"[{i}/{len(packages)}] Sideloading {pkg}...")
        try:
            apk_path = adb(src, 'shell', 'pm', 'path', pkg).splitlines()[0].replace('package:', '').strip()
            local_apk = os.path.join(temp_dir, f"{pkg}.apk")
            subprocess.run(['adb', '-s', src, 'pull', apk_path, local_apk], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if os.path.exists(local_apk):
                res = subprocess.run(['adb', '-s', dst, 'install', '-r', local_apk], capture_output=True, text=True)
                if 'Success' in res.stdout:
                    print(f"   ✅ Installed {pkg}")
                    success += 1
                else:
                    print(f"   ⚠️ Failed to install {pkg}: {res.stderr.strip() or res.stdout.strip()}")
                    failed += 1
                os.remove(local_apk)
            else:
                print(f"   ⚠️ Could not pull APK for {pkg}")
                failed += 1
        except Exception as e:
            print(f"   ⚠️ Error migrating {pkg}: {e}")
            failed += 1

    subprocess.run(['rm', '-rf', temp_dir])
    print(f"\n🎉 App clone complete: {success} succeeded, {failed} failed.")

def cmd_scan(args):
    dst = get_serial(args.target)
    scan_media(dst)

def main():
    parser = argparse.ArgumentParser(description="Fleet Android Migration & Media Management Tool")
    subparsers = parser.add_subparsers(dest="action", required=True)

    # migrate-media
    p_mig = subparsers.add_parser("media", help="Direct device-to-device media migration")
    p_mig.add_argument("--source", "-s", required=True, help="Source device serial or profile name")
    p_mig.add_argument("--target", "-t", required=True, help="Target device serial or profile name")
    p_mig.set_defaults(func=cmd_migrate_media)

    # backup-media
    p_bak = subparsers.add_parser("backup-media", help="Pull media from device to host directory")
    p_bak.add_argument("--source", "-s", required=True, help="Source device serial or profile name")
    p_bak.add_argument("--out", "-o", required=True, help="Local destination directory")
    p_bak.set_defaults(func=cmd_backup_media)

    # restore-media
    p_res = subparsers.add_parser("restore-media", help="Push media from host directory to device")
    p_res.add_argument("--target", "-t", required=True, help="Target device serial or profile name")
    p_res.add_argument("--input", "-i", required=True, help="Local directory containing media folders")
    p_res.set_defaults(func=cmd_restore_media)

    # clone-apps
    p_apps = subparsers.add_parser("clone-apps", help="Extract and install 3rd party apps between devices")
    p_apps.add_argument("--source", "-s", required=True, help="Source device serial or profile name")
    p_apps.add_argument("--target", "-t", required=True, help="Target device serial or profile name")
    p_apps.add_argument("--filter", "-f", default=None, help="Substring filter on package name")
    p_apps.set_defaults(func=cmd_clone_apps)

    # scan
    p_scan = subparsers.add_parser("scan", help="Force Android MediaScanner refresh")
    p_scan.add_argument("--target", "-t", required=True, help="Target device serial or profile name")
    p_scan.set_defaults(func=cmd_scan)

    args = parser.parse_args()
    args.func(args)

if __name__ == '__main__':
    main()
