import SwiftUI
import AppKit
import WakeMateCore

@main
struct WakeMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var powerMonitor: PowerMonitor
    @StateObject private var sleepController: SleepController
    @StateObject private var sessionManager: SessionManager

    init() {
        let monitor = PowerMonitor()
        let controller = SleepController()
        let session = SessionManager(sleepController: controller, powerMonitor: monitor)

        _powerMonitor = StateObject(wrappedValue: monitor)
        _sleepController = StateObject(wrappedValue: controller)
        _sessionManager = StateObject(wrappedValue: session)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                session: sessionManager,
                power: powerMonitor,
                sleep: sleepController
            )
            .onAppear {
                appDelegate.sessionManager = sessionManager
                powerMonitor.start()
                sleepController.refreshHelperStatus()
            }
        } label: {
            MenuBarLabelView(session: sessionManager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

// MARK: - App Delegate for Lifecycle & Failsafes

final class AppDelegate: NSObject, NSApplicationDelegate {
    var sessionManager: SessionManager?
    private let signalTrap = SignalTrap()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let failsafe = FailsafeSleepHelper(wrapping: PMSetSleepHelper())
        _ = try? failsafe.recoverAfterUncleanExit()

        signalTrap.install { [weak self] in
            self?.sessionManager?.handleTermination()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionManager?.handleTermination()
    }
}
