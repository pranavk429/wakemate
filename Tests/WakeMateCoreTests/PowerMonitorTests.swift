import Foundation
@testable import WakeMateCore

public enum PowerMonitorTests {
    public static func runAll() {
        runAsyncTest("PowerMonitor.publishesInitialSnapshotOnStart") {
            let provider = FakePowerSourceProvider(snapshot: onBattery(42))
            let monitor = PowerMonitor(provider: provider)
            monitor.start()
            expect(monitor.isACConnected == false)
            expect(monitor.batteryPercentage == 42)
            expect(monitor.snapshot == onBattery(42))
            expect(provider.isObserving)
        }

        runAsyncTest("PowerMonitor.publishesChangesFromPowerSourceNotifications") {
            let provider = FakePowerSourceProvider(snapshot: onBattery(42))
            let monitor = PowerMonitor(provider: provider)
            monitor.start()
            provider.emit(onAC(77))
            expect(monitor.isACConnected)
            expect(monitor.batteryPercentage == 77)
            expect(monitor.isCharging)
        }

        runAsyncTest("PowerMonitor.fallsBackToPollingWhenNotificationRegistrationFails") {
            let provider = FakePowerSourceProvider()
            provider.shouldFailToObserve = true
            let monitor = PowerMonitor(provider: provider)
            monitor.start()
            expect(monitor.isUsingFallbackPolling)
            expect(monitor.lastError == .notificationRegistrationFailed)
            monitor.stop()
            expect(monitor.isUsingFallbackPolling == false)
        }

        runAsyncTest("PowerMonitor.stopHaltsObservation") {
            let provider = FakePowerSourceProvider(snapshot: onAC(80))
            let monitor = PowerMonitor(provider: provider)
            monitor.start()
            monitor.stop()
            provider.emit(onBattery(20))
            expect(provider.isObserving == false)
            expect(monitor.batteryPercentage == 80)
        }
    }
}
