import Foundation
@testable import WakeMateCore

public enum PowerPolicyTests {
    public static func runAll() {
        runTest("PowerPolicy.noViolationOnACWithAllRulesEnabled") {
            let policy = PowerPolicy(requiresPowerAdapter: true, endsOnLowBattery: true, batteryCutoff: 30)
            expect(policy.violation(for: onAC(50)) == nil)
        }

        runTest("PowerPolicy.unpluggedAdapterViolatesWhenAdapterRequired") {
            let policy = PowerPolicy(requiresPowerAdapter: true, endsOnLowBattery: false, batteryCutoff: 30)
            expect(policy.violation(for: onBattery(90)) == .adapterDisconnected)
        }

        runTest("PowerPolicy.batteryAtCutoffIsViolation") {
            let policy = PowerPolicy(requiresPowerAdapter: false, endsOnLowBattery: true, batteryCutoff: 30)
            expect(policy.violation(for: onBattery(30)) == .batteryAtOrBelowCutoff(percentage: 30, cutoff: 30))
        }

        runTest("PowerPolicy.batteryAboveCutoffIsAllowed") {
            let policy = PowerPolicy(requiresPowerAdapter: false, endsOnLowBattery: true, batteryCutoff: 30)
            expect(policy.violation(for: onBattery(31)) == nil)
        }

        runTest("PowerPolicy.lowBatteryRuleIgnoredWhileOnAC") {
            let policy = PowerPolicy(requiresPowerAdapter: false, endsOnLowBattery: true, batteryCutoff: 30)
            expect(policy.violation(for: onAC(10)) == nil)
        }

        runTest("PowerPolicy.disabledLowBatteryRuleAllowsAnyLevel") {
            let policy = PowerPolicy(requiresPowerAdapter: false, endsOnLowBattery: false, batteryCutoff: 30)
            expect(policy.violation(for: onBattery(3)) == nil)
        }

        runTest("PowerPolicy.machineWithoutBatteryNeverTripsLowBatteryRule") {
            let policy = PowerPolicy(requiresPowerAdapter: false, endsOnLowBattery: true, batteryCutoff: 80)
            let snapshot = PowerSnapshot(isACConnected: false, batteryPercentage: nil, isCharging: false)
            expect(policy.violation(for: snapshot) == nil)
        }

        runTest("PowerPolicy.adapterViolationTakesPrecedenceOverBattery") {
            let policy = PowerPolicy(requiresPowerAdapter: true, endsOnLowBattery: true, batteryCutoff: 30)
            expect(policy.violation(for: onBattery(5)) == .adapterDisconnected)
        }

        runTest("PowerPolicy.cutoffIsClampedToSupportedRange") {
            let cases = [(5, 10), (10, 10), (55, 55), (80, 80), (95, 80)]
            for (input, expectedValue) in cases {
                expect(PowerPolicy(requiresPowerAdapter: false, endsOnLowBattery: true, batteryCutoff: input).batteryCutoff == expectedValue)
            }
        }

        runTest("PowerPolicy.loadsDefaultsWhenNothingStored") {
            let defaults = try require(UserDefaults(suiteName: "wakemate.tests.\(UUID().uuidString)"))
            expect(PowerPolicy.load(from: defaults) == PowerPolicy(requiresPowerAdapter: false, endsOnLowBattery: true, batteryCutoff: 30))
        }

        runTest("PowerPolicy.loadsStoredValues") {
            let defaults = try require(UserDefaults(suiteName: "wakemate.tests.\(UUID().uuidString)"))
            defaults.set(true, forKey: SettingsKey.requirePowerAdapter)
            defaults.set(false, forKey: SettingsKey.endOnLowBattery)
            defaults.set(55, forKey: SettingsKey.batteryCutoff)
            expect(PowerPolicy.load(from: defaults) == PowerPolicy(requiresPowerAdapter: true, endsOnLowBattery: false, batteryCutoff: 55))
        }
    }
}
