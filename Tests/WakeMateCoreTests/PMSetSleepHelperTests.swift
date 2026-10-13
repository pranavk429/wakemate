import Foundation
@testable import WakeMateCore

public enum PMSetSleepHelperTests {
    public static func runAll() {
        runTest("PMSetSleepHelper.disableSystemSleepRunsScopedNonInteractiveSudo") {
            let runner = FakeCommandRunner()
            let helper = PMSetSleepHelper(runner: runner)
            try helper.disableSystemSleep(until: nil)
            expect(runner.invocations == [
                .init(executable: "/usr/bin/sudo", arguments: ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"]),
            ])
        }

        runTest("PMSetSleepHelper.enableSystemSleepRunsScopedNonInteractiveSudo") {
            let runner = FakeCommandRunner()
            let helper = PMSetSleepHelper(runner: runner)
            try helper.enableSystemSleep()
            expect(runner.invocations == [
                .init(executable: "/usr/bin/sudo", arguments: ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]),
            ])
        }

        runTest("PMSetSleepHelper.passwordPromptIsReportedAsNotAuthorized") {
            let runner = FakeCommandRunner()
            let helper = PMSetSleepHelper(runner: runner)
            runner.handler = { _ in CommandResult(exitCode: 1, stdout: "", stderr: "sudo: a password is required\n") }
            expectThrows(SleepHelperError.notAuthorized) {
                try helper.enableSystemSleep()
            }
        }

        runTest("PMSetSleepHelper.otherFailuresSurfaceCommandExitCodeAndStderr") {
            let runner = FakeCommandRunner()
            let helper = PMSetSleepHelper(runner: runner)
            runner.handler = { _ in CommandResult(exitCode: 2, stdout: "", stderr: "boom\n") }
            expectThrows(SleepHelperError.commandFailed(
                command: "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1", exitCode: 2, stderr: "boom"
            )) {
                try helper.disableSystemSleep(until: nil)
            }
        }

        runTest("PMSetSleepHelper.helperIsInstalledWhenBothRulesArePermitted") {
            let runner = FakeCommandRunner()
            let helper = PMSetSleepHelper(runner: runner)
            expect(helper.isInstalled())
            expect(runner.invocations == [
                .init(executable: "/usr/bin/sudo", arguments: ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]),
                .init(executable: "/usr/bin/sudo", arguments: ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"]),
            ])
        }

        runTest("PMSetSleepHelper.helperIsNotInstalledWhenRestoreRuleIsMissing") {
            let runner = FakeCommandRunner()
            let helper = PMSetSleepHelper(runner: runner)
            runner.handler = { invocation in
                CommandResult(exitCode: invocation.arguments.last == "0" ? 1 : 0, stdout: "", stderr: "")
            }
            expect(helper.isInstalled() == false)
        }

        runTest("PMSetSleepHelper.helperIsNotInstalledWhenSudoCannotLaunch") {
            let runner = FakeCommandRunner()
            let helper = PMSetSleepHelper(runner: runner)
            runner.launchError = CommandError.launchFailed(executable: "/usr/bin/sudo", reason: "missing")
            expect(helper.isInstalled() == false)
        }

        runTest("PMSetSleepHelper.readsSleepDisabledFlagFromPmset") {
            let cases: [(String, Bool)] = [
                ("System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n standby 1\n", true),
                ("System-wide power settings:\n SleepDisabled\t\t0\n", false),
                ("Currently in use:\n standby 1\n", false)
            ]
            for (output, expectedBool) in cases {
                let runner = FakeCommandRunner()
                let helper = PMSetSleepHelper(runner: runner)
                runner.handler = { _ in CommandResult(exitCode: 0, stdout: output, stderr: "") }
                expect(try helper.isSystemSleepDisabled() == expectedBool)
                expect(runner.invocations == [.init(executable: "/usr/bin/pmset", arguments: ["-g"])])
            }
        }

        runTest("PMSetSleepHelper.sleepNowRunsUnprivilegedPmset") {
            let runner = FakeCommandRunner()
            let helper = PMSetSleepHelper(runner: runner)
            try helper.sleepNow()
            expect(runner.invocations == [.init(executable: "/usr/bin/pmset", arguments: ["sleepnow"])])
        }
    }
}
