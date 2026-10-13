# WakeMate ⚡️

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B-black.svg?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?logo=swift)](https://swift.org)
[![Tests](https://img.shields.io/badge/Tests-59%20Passing%20(100%25)-brightgreen.svg)]()
[![Footprint](https://img.shields.io/badge/Memory-~26%20MB-blueviolet.svg)]()
[![CPU](https://img.shields.io/badge/Idle%20CPU-0.0%25-success.svg)]()

A lightweight, native macOS Menu Bar utility in Swift & SwiftUI that keeps your MacBook awake while long-running AI agents, local LLMs, builds, or scripts run — **including when your laptop lid is closed**, without needing an external monitor.

Designed from the ground up for **maximum battery efficiency, rock-solid security, and zero background drain**.

---

## Why WakeMate?

Most sleep-prevention apps (like Amphetamine or Caffeinate) either keep displays burning power, fail to work when the laptop lid is closed without an external display, or drain your battery to 0% in your backpack. 

WakeMate solves this with an intelligent dual-engine architecture:

| Feature | Standard Utilities | WakeMate |
| :--- | :--- | :--- |
| **Closed-Lid Mode** | Requires external display plugged in | **Works anywhere** (via scoped `pmset` helper) |
| **Battery Protection** | Keeps running until battery reaches 0% | **Configurable cutoff (10%–80%)**, auto-stops |
| **Power Adapter Policy** | Ignored | **Auto-stop when charger is unplugged** |
| **Display Sleep** | Often keeps screen illuminated | **Allows screen to turn off** (saves ~70–80% battery) |
| **Idle Resource Usage** | 100–400 MB (Electron/runtimes), 1–5% CPU | **~26 MB footprint, 0.0% CPU** (event-driven IOKit) |
| **Failsafe Watchdog** | Sleep disabled permanently if app crashes | **Out-of-process root watchdog** restores sleep |
| **Telemetry & Network** | Often collects metrics | **Zero network requests**, 100% private & offline |

---

## How It Works

WakeMate uses a dual sleep-prevention architecture depending on the lid state:

```
                          ┌──────────────────────────┐
                          │   WakeMate Session Run   │
                          └─────────────┬────────────┘
                                        │
                         Is Closed-Lid Mode Active?
                                       / \
                                      /   \
                                  No /     \ Yes
                                    /       \
  ┌────────────────────────────────────┐ ┌───────────────────────────────────┐
  │         Open-Lid Engine            │ │        Closed-Lid Engine          │
  │ • IOKit Power Assertion            │ │ • Scoped non-interactive pmset    │
  │ • Type: PreventUserIdleSystemSleep │ │ • Heartbeat lease file updated    │
  │ • Display backlight turns OFF      │ │ • Root watchdog checks every 60s  │
  └────────────────────────────────────┘ └───────────────────────────────────┘
```

1. **Open-Lid**: Registers a native IOKit power assertion (`kIOPMAssertionTypePreventUserIdleSystemSleep`). The CPU stays active, but the display is allowed to turn off and sleep, cutting power consumption by 70–80%.
2. **Closed-Lid**: Toggles `/usr/bin/pmset -a disablesleep 1` via a dedicated, strictly scoped sudoers rule.
3. **Instant Sleep on Clamshell**: If battery drops to your cutoff or the charger is unplugged while the lid is closed, WakeMate immediately calls `pmset sleepnow` so your closed Mac sleeps instantly and will never overheat in a bag.

---

## Battery & Memory Optimization

WakeMate is engineered to be invisible to your system resources:

- **Physical Memory Footprint**: **~26 MB** (measured via macOS `footprint`).
- **CPU Utilization**: **0.0%** at idle with process in kernel sleeping state (`S`).
- **Adaptive Timer Coalescing**:
  - Countdown sessions use system-coalesced timers (`tolerance = 0.5s` to `5.0s`), allowing Apple Silicon efficiency cores to stay in deep sleep states.
  - Indefinite sessions tick only once every **30 seconds** (a **96.7% reduction** in CPU wakeups).
- **Event-Driven Power Monitoring**: No background polling loops. WakeMate hooks directly into `IOPSNotificationCreateRunLoopSource`, waking only when macOS broadcasts an actual battery state change.

---

## Quick Start for Users

### Option 1: Download Pre-built Release
1. Download `WakeMate.zip` from [GitHub Releases](https://github.com/pranavk429/wakemate/releases).
2. Unzip and drag `WakeMate.app` into your `/Applications/` folder.
3. Open `WakeMate.app` from Spotlight or Applications.

### Option 2: Build From Source
WakeMate has zero third-party dependencies and builds with standard Swift / Xcode Command Line Tools:

```bash
git clone https://github.com/pranavk429/wakemate.git
cd wakemate

# Build optimized release bundle
./Scripts/build-app.sh release

# Launch WakeMate
open build/WakeMate.app
```

---

## Enabling Closed-Lid Mode (Optional)

WakeMate works out-of-the-box for open-lid sleep prevention. If you want sleep prevention to continue when you **close the lid**, install the lightweight helper:

```bash
sudo ./Scripts/install-helper.sh
```

### What this does:
1. **Installs a tightly scoped sudoers rule** (`/etc/sudoers.d/wakemate`):
   Allows *only* your specific user account to run `/usr/bin/pmset -a disablesleep 1` and `0` without a password prompt. No other commands or arguments can be run as root.
2. **Installs an out-of-process watchdog** (`com.wakemate.watchdog`):
   Runs as a LaunchDaemon every 60 seconds. If WakeMate is ever force-quit (`kill -9`), crashes, or hangs, the watchdog verifies the lease file (`~/Library/Application Support/WakeMate/sleep.lease`) and automatically restores normal system sleep.

### To uninstall the helper:
```bash
sudo ./Scripts/uninstall-helper.sh
```
Restores normal system sleep and removes the sudoers rule and watchdog LaunchDaemon completely.

---

## Settings & Customization (`⌘,`)

Access Settings from the popover or press `⌘,`:

- **Require a power adapter**: Automatically halts the session and restores sleep if your MacBook is unplugged from AC power.
- **End sessions on low battery**: Automatically halts the session when the battery drops to or below your threshold.
- **Battery cutoff**: Adjustable slider/stepper from **10% to 80%** (default: **30%**).
- **Show timer in menu bar**: Toggle whether the live countdown appears in the menu bar label or only inside the popover.

---

## Running the Test Suite

WakeMate includes 59 automated unit and integration tests covering power policies, IOKit notifications, pmset execution, lease recovery, and session state machines:

```bash
swift run WakeMateTests
```

---

## Security & Privacy Guarantee

- **Zero Network Access**: WakeMate contains zero networking code and makes zero HTTP/socket connections.
- **Zero Analytics or Telemetry**: No tracking, cookies, or diagnostics transmitted anywhere.
- **No Paid Apple Developer ID Required**: Works seamlessly for personal and open-source use with standard ad-hoc signing.
- **Strict Least-Privilege**: The helper rule only permits toggling the `disablesleep` flag.

---

## License

This project is licensed under the [MIT License](LICENSE).
