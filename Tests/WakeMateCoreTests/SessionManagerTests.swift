import Foundation
@testable import WakeMateCore

public enum SessionManagerTests {
    public static func runAll() {
        runAsyncTest("SessionManager.startingTimedSessionSetsDeadlineAndPreventsSleep") {
            let h = SessionHarness()
            try h.session.start(duration: .oneHour)
            let now = h.clock.now()
            expect(h.session.state == .active(startedAt: now, endsAt: now.addingTimeInterval(3600), duration: .oneHour))
            expect(h.session.remaining == 3600)
            expect(h.controller.isPreventingIdleSleep)
            expect(h.controller.isPreventingClamshellSleep)
            expect(h.ticker.isRunning)
        }

        runAsyncTest("SessionManager.indefiniteSessionHasNoDeadline") {
            let h = SessionHarness()
            try h.session.start(duration: .indefinite)
            expect(h.session.state == .active(startedAt: h.clock.now(), endsAt: nil, duration: .indefinite))
            expect(h.session.remaining == nil)
        }

        runAsyncTest("SessionManager.startUsesSelectedDurationByDefault") {
            let h = SessionHarness()
            h.session.selectedDuration = .twoHours
            try h.session.start()
            expect(h.session.remaining == 7200)
        }

        runAsyncTest("SessionManager.startIsRefusedWhenPowerPolicyIsViolated") {
            let h = SessionHarness(
                policy: PowerPolicy(requiresPowerAdapter: true, endsOnLowBattery: true, batteryCutoff: 30),
                snapshot: onBattery(90)
            )
            expectThrows(SessionError.powerPolicyViolated(.adapterDisconnected)) {
                try h.session.start(duration: .oneHour)
            }
            expect(h.session.state == .idle)
            expect(h.assertions.created == 0)
            expect(h.session.lastErrorMessage != nil)
        }

        runAsyncTest("SessionManager.tickUpdatesRemainingTime") {
            let h = SessionHarness()
            try h.session.start(duration: .thirtyMinutes)
            h.clock.advance(by: 600)
            h.ticker.fire()
            expect(h.session.remaining == 1200)
        }

        runAsyncTest("SessionManager.sessionEndsWhenTimerExpiresAndSleepsClosedLid") {
            let h = SessionHarness()
            h.clamshell.lidClosed = true
            try h.session.start(duration: .thirtyMinutes)
            h.clock.advance(by: 1800)
            h.ticker.fire()
            expect(h.session.state == .idle)
            expect(h.session.lastStopReason == .timerExpired)
            expect(h.helper.calls == ["disable", "enable", "sleepNow"])
            expect(h.ticker.isRunning == false)
            expect(h.controller.isPreventingIdleSleep == false)
        }

        runAsyncTest("SessionManager.unpluggingAdapterWhenRequiredEndsSessionAndSleeps") {
            let h = SessionHarness(policy: PowerPolicy(requiresPowerAdapter: true, endsOnLowBattery: true, batteryCutoff: 30))
            h.clamshell.lidClosed = true
            try h.session.start(duration: .indefinite)
            h.power.emit(onBattery(80))
            expect(h.session.state == .idle)
            expect(h.session.lastStopReason == .powerViolation(.adapterDisconnected))
            expect(h.helper.calls == ["disable", "enable", "sleepNow"])
        }

        runAsyncTest("SessionManager.batteryDroppingToCutoffEndsSession") {
            let h = SessionHarness(
                policy: PowerPolicy(requiresPowerAdapter: false, endsOnLowBattery: true, batteryCutoff: 30),
                snapshot: onBattery(50)
            )
            try h.session.start(duration: .fourHours)
            h.power.emit(onBattery(31))
            expect(h.session.isActive)
            h.power.emit(onBattery(30))
            expect(h.session.state == .idle)
            expect(h.session.lastStopReason == .powerViolation(.batteryAtOrBelowCutoff(percentage: 30, cutoff: 30)))
        }

        runAsyncTest("SessionManager.tighteningSettingsMidSessionEndsSession") {
            let h = SessionHarness(policy: PowerPolicy(requiresPowerAdapter: false, endsOnLowBattery: false, batteryCutoff: 30), snapshot: onBattery(60))
            try h.session.start(duration: .oneHour)
            h.policy = PowerPolicy(requiresPowerAdapter: true, endsOnLowBattery: false, batteryCutoff: 30)
            h.notificationCenter.post(name: UserDefaults.didChangeNotification, object: nil)
            expect(h.session.state == .idle)
            expect(h.session.lastStopReason == .powerViolation(.adapterDisconnected))
        }

        runAsyncTest("SessionManager.userStopRestoresSleepWithoutForcingSleep") {
            let h = SessionHarness()
            h.clamshell.lidClosed = true
            try h.session.start(duration: .oneHour)
            h.session.stop()
            expect(h.helper.calls == ["disable", "enable"])
            expect(h.session.lastStopReason == .user)
            expect(h.session.remaining == nil)
        }

        runAsyncTest("SessionManager.readinessRequiresHelperPowerAndRunningSession") {
            let h = SessionHarness()
            expect(h.session.readiness == ReadinessStatus(helperInstalled: true, powerOK: true, sessionRunning: false))
            expect(h.session.readiness.isReadyToCloseLid == false)
            try h.session.start(duration: .oneHour)
            expect(h.session.readiness.isReadyToCloseLid)
        }

        runAsyncTest("SessionManager.readinessReflectsMissingHelper") {
            let h = SessionHarness(helperInstalled: false)
            try h.session.start(duration: .oneHour)
            expect(h.session.readiness.helperInstalled == false)
            expect(h.session.readiness.isReadyToCloseLid == false)
        }

        runAsyncTest("SessionManager.readinessReflectsPowerChanges") {
            let h = SessionHarness(policy: PowerPolicy(requiresPowerAdapter: true, endsOnLowBattery: true, batteryCutoff: 30))
            h.power.emit(onBattery(90))
            expect(h.session.readiness.powerOK == false)
        }

        runAsyncTest("SessionManager.heartbeatIsSentPeriodicallyDuringSession") {
            let h = SessionHarness()
            try h.session.start(duration: .oneHour)
            h.clock.advance(by: 5)
            h.ticker.fire()
            expect(h.helper.calls.contains("heartbeat") == false)
            h.clock.advance(by: SessionManager.heartbeatInterval)
            h.ticker.fire()
            expect(h.helper.calls.contains("heartbeat"))
        }

        runAsyncTest("SessionManager.terminationRestoresSleep") {
            let h = SessionHarness()
            try h.session.start(duration: .indefinite)
            h.session.handleTermination()
            expect(h.session.state == .idle)
            expect(h.session.lastStopReason == .appTerminating)
            expect(h.helper.calls == ["disable", "enable"])
        }
    }
}
