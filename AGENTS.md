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

```bash
just status                 # Show status dashboard (battery, Shizuku, NetBird, window) across all devices
just tune [device|all]      # Apply declarative settings (animations, 120Hz, DNS, keyboard, doze, debloat)
just start-shizuku          # Start elevated Shizuku daemon via ADB on all devices
just termux-provision [dev] # Bootstrap SSH keys, fleet aliases, and herdr access
just scrcpy [device]        # USB/Wi-Fi screen mirroring
just tablet-desk            # MatePad Pro desk companion mode (canvas + webcam)
```

## Directory Structure

* `devices/*.yaml`: Declarative device profiles (animations, DNS, doze whitelist, debloat, permissions).
* `scripts/apply-device.py`: Python engine applying YAML profiles to connected devices via ADB.
* `scripts/status.py`: Dashboard querying battery, thermal, and network state.
* `scripts/provision-termux.sh`: Termux environment bootstrapper.
