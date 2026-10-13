import Foundation
@testable import WakeMateCore

public enum SleepControllerTests {
    public static func runAll() {
        runAsyncTest("SleepController.activateCreatesSingleIdleSleepAssertion") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            try controller.activate(reason: "test", until: nil)
            try controller.activate(reason: "test", until: nil)
            expect(assertions.created == 1)
            expect(controller.isPreventingIdleSleep)
        }

        runAsyncTest("SleepController.activateWithInstalledHelperDisablesClamshellSleep") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            try controller.activate(reason: "test", until: nil)
            expect(helper.calls == ["disable"])
            expect(controller.isPreventingClamshellSleep)
            expect(controller.isHelperInstalled)
        }

        runAsyncTest("SleepController.activateWithoutHelperOnlyPreventsIdleSleep") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            helper.installed = false
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            try controller.activate(reason: "test", until: nil)
            expect(helper.calls.isEmpty)
            expect(controller.isPreventingIdleSleep)
            expect(controller.isPreventingClamshellSleep == false)
            expect(controller.isHelperInstalled == false)
        }

        runAsyncTest("SleepController.assertionFailureThrowsAndSkipsHelper") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            assertions.shouldFail = true
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            expectThrowsType(SleepControllerError.self) {
                try controller.activate(reason: "test", until: nil)
            }
            expect(helper.calls.isEmpty)
            expect(controller.isPreventingIdleSleep == false)
        }

        runAsyncTest("SleepController.clamshellFailureKeepsOpenLidProtectionAndReportsError") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            helper.failDisable = SleepHelperError.notAuthorized
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            try controller.activate(reason: "test", until: nil)
            expect(controller.isPreventingIdleSleep)
            expect(controller.isPreventingClamshellSleep == false)
            expect(controller.lastErrorMessage != nil)
        }

        runAsyncTest("SleepController.deactivateRestoresSleepAndReleasesAssertion") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            try controller.activate(reason: "test", until: nil)
            let errors = controller.deactivate(sleepImmediatelyIfLidClosed: false)
            expect(errors.isEmpty)
            expect(helper.calls == ["disable", "enable"])
            expect(assertions.released.count == 1)
            expect(controller.isPreventingIdleSleep == false)
            expect(controller.isPreventingClamshellSleep == false)
        }

        runAsyncTest("SleepController.deactivateRetriesRestoreOnceBeforeReportingFailure") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            try controller.activate(reason: "test", until: nil)
            helper.failEnable = SleepHelperError.notAuthorized
            let errors = controller.deactivate(sleepImmediatelyIfLidClosed: false)
            expect(errors.count == 1)
            expect(helper.calls == ["disable", "enable", "enable"])
            expect(controller.isPreventingClamshellSleep, "state must stay truthful when restore fails")
            expect(assertions.released.count == 1)
        }

        runAsyncTest("SleepController.deactivateSleepsImmediatelyWhenLidClosed") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            clamshell.lidClosed = true
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            try controller.activate(reason: "test", until: nil)
            controller.deactivate(sleepImmediatelyIfLidClosed: true)
            expect(helper.calls == ["disable", "enable", "sleepNow"])
        }

        runAsyncTest("SleepController.deactivateDoesNotForceSleepWhenLidOpen") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            clamshell.lidClosed = false
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            try controller.activate(reason: "test", until: nil)
            controller.deactivate(sleepImmediatelyIfLidClosed: true)
            expect(helper.calls.contains("sleepNow") == false)
        }

        runAsyncTest("SleepController.deactivateWithoutActivationIsNoOp") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            expect(controller.deactivate(sleepImmediatelyIfLidClosed: false).isEmpty)
            expect(helper.calls.isEmpty)
            expect(assertions.released.isEmpty)
        }

        runAsyncTest("SleepController.heartbeatForwardedOnlyWhileClamshellPreventionActive") {
            let assertions = FakeAssertionProvider()
            let helper = FakeSleepHelper()
            let clamshell = FakeClamshell()
            let controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)

            controller.heartbeat()
            expect(helper.calls.isEmpty)
            try controller.activate(reason: "test", until: nil)
            controller.heartbeat()
            expect(helper.calls == ["disable", "heartbeat"])
        }
    }
}
