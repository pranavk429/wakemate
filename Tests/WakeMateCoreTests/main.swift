import Foundation

print("========================================")
print("🧪 WakeMateCore Test Suite Starting...")
print("========================================\n")

TestContext.shared.reset()

print("--- [1/6] PowerPolicyTests ---")
PowerPolicyTests.runAll()

print("\n--- [2/6] PowerMonitorTests ---")
PowerMonitorTests.runAll()

print("\n--- [3/6] PMSetSleepHelperTests ---")
PMSetSleepHelperTests.runAll()

print("\n--- [4/6] FailsafeSleepHelperTests ---")
FailsafeSleepHelperTests.runAll()

print("\n--- [5/6] SleepControllerTests ---")
SleepControllerTests.runAll()

print("\n--- [6/6] SessionManagerTests ---")
SessionManagerTests.runAll()

let summary = TestContext.shared.summary
print("\n========================================")
if TestContext.shared.hasFailures {
    print("❌ TEST SUITE FAILED: \(summary.failed) failure(s) out of \(summary.total) tests.")
    print("========================================")
    exit(1)
} else {
    print("🎉 ALL \(summary.total) TESTS PASSED SUCCESSFULLY! (100% GREEN)")
    print("========================================")
    exit(0)
}
