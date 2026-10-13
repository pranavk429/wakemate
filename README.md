# WakeMate ⚡️

A native macOS 14+ Menu Bar utility in Swift & SwiftUI that keeps your MacBook awake while AI agents run — including when the lid is closed.

---

## Key Features

1. **Pure Menu Bar Utility (`LSUIElement = true`)**
   - Resides exclusively in the macOS Menu Bar via SwiftUI `MenuBarExtra(style: .window)`.
   - Shows active status indicator dot and live countdown timer in the menu bar label.
   - Popover controls for session duration (**30m**, **1h**, **2h**, **4h**, **Indefinite**).
   - 3-step readiness checklist for Closed-Lid Mode with dynamic **"Ready to close lid"** badge.

2. **Real-Time IOKit Power & Battery Monitoring (`PowerMonitor.swift`)**
   - Subscribes directly to `IOPSNotificationCreateRunLoopSource` and `IOPSCopyPowerSourcesInfo`.
   - Live battery percentage, charging state, and AC adapter connectivity.
   - Graceful fallback polling if IOKit notification registration ever fails.

3. **Power Policy Engine (`PowerPolicy.swift`)**
   - **Require a power adapter**: Immediately stops session and restores sleep if charger is disconnected.
   - **End sessions on low battery**: Automatically ends session when battery reaches or drops below cutoff (10% to 80%, default 30%).
   - Settings window (`⌘,`) backed by `@AppStorage`.

4. **Dual Sleep Prevention Architecture (`SleepController.swift`)**
   - **Open-Lid**: Native `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleSystemSleep`.
   - **Closed-Lid (Clamshell)**: Scoped non-interactive `/usr/bin/pmset -a disablesleep 1` / `0` via a dedicated `/etc/sudoers.d/wakemate` rule (no paid Apple Developer ID notarization required).
   - **Immediate Sleep on Clamshell**: When a session ends or violates power rules while the lid is closed, WakeMate automatically triggers `pmset sleepnow` so the closed laptop sleeps right away instead of draining battery.

5. **Defense-in-Depth Failsafe Watchdog Engine**
   - **Signal Traps**: Catches `SIGTERM` and `SIGINT` to restore sleep before process exits.
   - **Termination Hook**: `NSApplication.willTerminateNotification` restores sleep.
   - **Out-of-Process Watchdog**: Root LaunchDaemon (`com.wakemate.watchdog`) checks every 60 seconds against a lease file (`~/Library/Application Support/WakeMate/sleep.lease`). If the app crashes, is SIGKILLed, or hangs without sending heartbeats, the watchdog automatically restores `pmset -a disablesleep 0`.
   - **Startup Crash Recovery**: Automatically cleans up and restores sleep if launched after an unclean system reboot or crash.

---

## File Structure

```
wakemate/
├── Package.swift                             # Swift 6 SPM package manifest
├── Resources/
│   └── Info.plist                            # LSUIElement = true application plist
├── Scripts/
│   ├── build-app.sh                          # Compiles & bundles into WakeMate.app
│   ├── install-helper.sh                     # Sets up sudoers rule & watchdog daemon
│   ├── uninstall-helper.sh                   # Removes helper & daemon, restores sleep
│   └── wakemate-watchdog.sh                  # Out-of-process root failsafe watchdog
├── Sources/
│   ├── WakeMate/                             # SwiftUI Application Layer
│   │   ├── MenuBarLabelView.swift            # SF Symbol + active dot + timer
│   │   ├── PopoverView.swift                 # Popover window, controls & status
│   │   ├── ReadinessChecklistView.swift      # 3-step closed-lid checklist & badge
│   │   ├── SettingsView.swift                # Settings window (⌘,) via @AppStorage
│   │   └── WakeMateApp.swift                 # App entry point & lifecycle hooks
│   └── WakeMateCore/                         # Business & OS Integration Layer
│       ├── Failsafe/
│       │   └── SignalTrap.swift              # POSIX signal handler (SIGTERM/SIGINT)
│       ├── Power/
│       │   ├── PowerMonitor.swift            # IOKit run-loop notification provider
│       │   └── PowerPolicy.swift             # Policy rules, cutoff clamping & storage
│       ├── Session/
│       │   └── SessionManager.swift          # Session timer, ticks, heartbeat & state
│       └── Sleep/
│           ├── CommandRunner.swift           # Safe process runner with timeouts
│           ├── SleepController.swift         # IOPMAssertion + SleepHelper coordinator
│           └── SleepHelper.swift             # pmset implementation & lease decorator
└── Tests/
    └── WakeMateCoreTests/                    # 59 Unit & Integration Tests
        ├── FailsafeSleepHelperTests.swift
        ├── MiniTesting.swift                 # Zero-dependency test runner
        ├── PMSetSleepHelperTests.swift
        ├── PowerMonitorTests.swift
        ├── PowerPolicyTests.swift
        ├── SessionManagerTests.swift
        ├── SleepControllerTests.swift
        ├── TestDoubles.swift                 # Fakes for IOKit, pmset, clock, ticker
        └── main.swift                        # Test executable entry point
```

---

## Setup & Usage

### 1. Run Unit Tests (100% Green)
```bash
swift run WakeMateTests
```

### 2. Build the App Bundle
```bash
./Scripts/build-app.sh release
# Output: build/WakeMate.app
```

### 3. Install the Privileged Helper (For Closed-Lid Mode)
```bash
sudo ./Scripts/install-helper.sh
```
This performs two safe steps:
1. Validates and installs `/etc/sudoers.d/wakemate` allowing *only* your user to run `/usr/bin/pmset -a disablesleep 1` and `0` without password prompts.
2. Installs the root LaunchDaemon `com.wakemate.watchdog` to safeguard against app crashes and hung states.

### 4. Launch WakeMate
```bash
open build/WakeMate.app
```

### 5. Uninstall Helper (Optional)
```bash
sudo ./Scripts/uninstall-helper.sh
```
Restores normal system sleep and cleans up `/etc/sudoers.d/wakemate` and the watchdog daemon.
