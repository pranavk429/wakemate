import Foundation
@testable import WakeMateCore

public enum FailsafeSleepHelperTests {
    public static func runAll() {
        runTest("FailsafeSleepHelper.leaseIsWrittenBeforeSleepIsDisabled") {
            let store = SleepLeaseStore(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("wakemate-test-\(UUID().uuidString).lease")
            )
            defer { try? store.clear() }
            let inner = FakeSleepHelper()
            let clock = FakeClock(Date(timeIntervalSince1970: 2_000_000))
            let helper = FailsafeSleepHelper(wrapping: inner, leaseStore: store, processID: 4242, clock: clock)

            var leaseSeenByPmset: SleepLease?
            inner.onDisable = { leaseSeenByPmset = store.read() }
            let deadline = clock.now().addingTimeInterval(3600)

            try helper.disableSystemSleep(until: deadline)

            expect(leaseSeenByPmset == SleepLease(pid: 4242, expiresAt: deadline, heartbeatAt: clock.now()))
        }

        runTest("FailsafeSleepHelper.failedDisableRemovesLease") {
            let store = SleepLeaseStore(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("wakemate-test-\(UUID().uuidString).lease")
            )
            defer { try? store.clear() }
            let inner = FakeSleepHelper()
            let clock = FakeClock(Date(timeIntervalSince1970: 2_000_000))
            let helper = FailsafeSleepHelper(wrapping: inner, leaseStore: store, processID: 4242, clock: clock)

            inner.failDisable = SleepHelperError.notAuthorized
            expectThrows(SleepHelperError.notAuthorized) {
                try helper.disableSystemSleep(until: nil)
            }
            expect(store.read() == nil)
        }

        runTest("FailsafeSleepHelper.enableRemovesLease") {
            let store = SleepLeaseStore(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("wakemate-test-\(UUID().uuidString).lease")
            )
            defer { try? store.clear() }
            let inner = FakeSleepHelper()
            let clock = FakeClock(Date(timeIntervalSince1970: 2_000_000))
            let helper = FailsafeSleepHelper(wrapping: inner, leaseStore: store, processID: 4242, clock: clock)

            try helper.disableSystemSleep(until: nil)
            try helper.enableSystemSleep()
            expect(store.read() == nil)
            expect(inner.calls == ["disable", "enable"])
        }

        runTest("FailsafeSleepHelper.failedEnableKeepsLeaseForWatchdog") {
            let store = SleepLeaseStore(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("wakemate-test-\(UUID().uuidString).lease")
            )
            defer { try? store.clear() }
            let inner = FakeSleepHelper()
            let clock = FakeClock(Date(timeIntervalSince1970: 2_000_000))
            let helper = FailsafeSleepHelper(wrapping: inner, leaseStore: store, processID: 4242, clock: clock)

            try helper.disableSystemSleep(until: nil)
            inner.failEnable = SleepHelperError.notAuthorized
            expectThrows(SleepHelperError.notAuthorized) {
                try helper.enableSystemSleep()
            }
            expect(store.read() != nil)
        }

        runTest("FailsafeSleepHelper.heartbeatRefreshesLeaseTimestamp") {
            let store = SleepLeaseStore(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("wakemate-test-\(UUID().uuidString).lease")
            )
            defer { try? store.clear() }
            let inner = FakeSleepHelper()
            let clock = FakeClock(Date(timeIntervalSince1970: 2_000_000))
            let helper = FailsafeSleepHelper(wrapping: inner, leaseStore: store, processID: 4242, clock: clock)

            try helper.disableSystemSleep(until: nil)
            clock.advance(by: 30)
            helper.heartbeat()
            expect(store.read()?.heartbeatAt == clock.now())
        }

        runTest("FailsafeSleepHelper.heartbeatWithoutActiveLeaseWritesNothing") {
            let store = SleepLeaseStore(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("wakemate-test-\(UUID().uuidString).lease")
            )
            let inner = FakeSleepHelper()
            let clock = FakeClock(Date(timeIntervalSince1970: 2_000_000))
            let helper = FailsafeSleepHelper(wrapping: inner, leaseStore: store, processID: 4242, clock: clock)

            helper.heartbeat()
            expect(store.read() == nil)
        }

        runTest("FailsafeSleepHelper.recoveryRestoresSleepWhenStaleLeaseExists") {
            let store = SleepLeaseStore(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("wakemate-test-\(UUID().uuidString).lease")
            )
            defer { try? store.clear() }
            let inner = FakeSleepHelper()
            let clock = FakeClock(Date(timeIntervalSince1970: 2_000_000))
            let helper = FailsafeSleepHelper(wrapping: inner, leaseStore: store, processID: 4242, clock: clock)

            try store.write(SleepLease(pid: 1, expiresAt: nil, heartbeatAt: clock.now()))
            expect(try helper.recoverAfterUncleanExit())
            expect(inner.calls == ["enable"])
            expect(store.read() == nil)
        }

        runTest("FailsafeSleepHelper.recoveryWithoutLeaseDoesNothing") {
            let store = SleepLeaseStore(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("wakemate-test-\(UUID().uuidString).lease")
            )
            let inner = FakeSleepHelper()
            let clock = FakeClock(Date(timeIntervalSince1970: 2_000_000))
            let helper = FailsafeSleepHelper(wrapping: inner, leaseStore: store, processID: 4242, clock: clock)

            expect(try helper.recoverAfterUncleanExit() == false)
            expect(inner.calls.isEmpty)
        }

        runTest("FailsafeSleepHelper.leaseSerializationRoundTrips") {
            let timed = SleepLease(pid: 77, expiresAt: Date(timeIntervalSince1970: 1_700_000_000), heartbeatAt: Date(timeIntervalSince1970: 1_699_999_000))
            let indefinite = SleepLease(pid: 78, expiresAt: nil, heartbeatAt: Date(timeIntervalSince1970: 1_699_999_000))
            expect(SleepLease(serialized: timed.serialized()) == timed)
            expect(SleepLease(serialized: indefinite.serialized()) == indefinite)
            expect(indefinite.serialized().contains("expires=0\n"))
            expect(SleepLease(serialized: "garbage") == nil)
        }
    }
}
