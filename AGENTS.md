# android-config

Declarative configuration, fleet management, and automation tooling for Android devices in the Kleinbem fleet.

## Devices

| Identifier | Model | Serial | IP | Role |
| :--- | :--- | :--- | :--- | :--- |
| **phone** | Samsung Galaxy XCover 6 Pro | `R5CX31EERDT` | `10.0.0.8` | Primary mobile, NetBird, Termux |
| **tablet** | Huawei MatePad Pro (MRX-W09) | `QBK6R20825000010` | `10.0.0.215` | Desk companion, Weylus, Lawnchair |
| **dhirujaan** | Samsung Galaxy | `RFCT90BVPNE` | `10.0.0.238` | Family device |
| **phone-old** | Samsung Galaxy XCover 6 Pro | `R5CW617ZWCF` | - | Hardware repair / backup |

## Key Recipes

### Fleet Administration
```bash
just status                         # Show status dashboard (battery, Shizuku, NetBird, foreground)
just tune [device|all]              # Apply declarative settings (animations, 120Hz, DNS, keyboard, doze, debloat)
just start-shizuku                  # Start elevated Shizuku daemon via ADB on all devices
just termux-provision [device]      # Bootstrap SSH keys, fleet aliases, and herdr access
```

### Migration & Data Management
```bash
just migrate-media [src] [dst]      # Move WhatsApp, DCIM, and downloads between devices
just backup-media [src] [out_dir]   # Pull WhatsApp, photos, and recordings to local folder
just restore-media [in_dir] [dst]   # Push local media backup to device and trigger MediaScanner
just clone-apps [src] [dst] [flt]   # Extract third-party APKs from src and install on dst
just media-scan [target]            # Force Android MediaScanner to index files
```

### Diagnostics & Remote Control
```bash
just shell [target]                 # Interactive ADB shell into selected device
just screenshot [target] [out.png]  # Capture high-res screen directly to host machine
just list-apps [target]             # List all installed 3rd party packages
just wifi-adb [target]              # Switch to ADB TCP/IP on port 5555 and connect
just scrcpy [device]                # USB/Wi-Fi screen mirroring
just tablet-desk                    # MatePad Pro desk companion mode (Weylus canvas + DroidCam)
```

## Documentation & Runbooks

* **[docs/ADB_COMMANDS.md](docs/ADB_COMMANDS.md)**: Exhaustive catalog and runbook of every low-level `adb`, `pm`, `settings`, `dumpsys`, and `appops` command used to configure the devices.

## Directory Structure

* `devices/*.yaml`: Declarative device profiles (animations, refresh rate, DNS, keyboard, launcher, doze whitelist, debloat, AppOps, and settings).
* `docs/ADB_COMMANDS.md`: Low-level ADB command reference.
* `scripts/apply-device.py`: Python tuning engine applying YAML profiles via ADB.
* `scripts/migrate.py`: Direct migration and backup tool for WhatsApp, DCIM, and APKs.
* `scripts/status.py`: Dashboard querying battery, thermal, and network state.
* `scripts/provision-termux.sh`: Termux environment bootstrapper.
