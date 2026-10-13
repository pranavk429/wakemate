import Foundation
@testable import WakeMateCore

// MARK: - Power

@MainActor
final class FakePowerSourceProvider: PowerSourceProviding {
    var snapshot: PowerSnapshot
    var shouldFailToObserve = false
    private(set) var isObserving = false
    private var onChange: (@MainActor () -> Void)?

    init(snapshot: PowerSnapshot = PowerSnapshot(isACConnected: true, batteryPercentage: 100, isCharging: false)) {
        self.snapshot = snapshot
    }

    func currentSnapshot() -> PowerSnapshot { snapshot }

    func startObserving(onChange: @escaping @MainActor () -> Void) throws {
        if shouldFailToObserve { throw PowerMonitorError.notificationRegistrationFailed }
        self.onChange = onChange
        isObserving = true
    }

    func stopObserving() {
        onChange = nil
        isObserving = false
    }

    /// Simulates IOKit posting a power-source change notification.
    func emit(_ newSnapshot: PowerSnapshot) {
        snapshot = newSnapshot
        onChange?()
    }
}

// MARK: - Sleep

final class FakeAssertionProvider: PowerAssertionProviding, @unchecked Sendable {
    var shouldFail = false
    private(set) var created = 0
    private(set) var released: [PowerAssertionHandle] = []
    private var nextID: UInt32 = 1

    func createPreventIdleSleepAssertion(reason: String) throws -> PowerAssertionHandle {
        if shouldFail { throw SleepControllerError.assertionCreationFailed(code: -1) }
        created += 1
        defer { nextID += 1 }
        return PowerAssertionHandle(rawValue: nextID)
    }

    func release(_ handle: PowerAssertionHandle) throws {
        released.append(handle)
    }
}

final class FakeSleepHelper: SleepHelperProtocol, @unchecked Sendable {
    var installed = true
    var failDisable: Error?
    var failEnable: Error?
    var sleepDisabled = false
    var onDisable: (() -> Void)?
    private(set) var calls: [String] = []

    func isInstalled() -> Bool { installed }

    func disableSystemSleep(until deadline: Date?) throws {
        calls.append("disable")
        onDisable?()
        if let failDisable { throw failDisable }
        sleepDisabled = true
    }

    func enableSystemSleep() throws {
        calls.append("enable")
        if let failEnable { throw failEnable }
        sleepDisabled = false
    }

    func isSystemSleepDisabled() throws -> Bool { sleepDisabled }

    func sleepNow() throws { calls.append("sleepNow") }

    func heartbeat() { calls.append("heartbeat") }
}

final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
    }

    private(set) var invocations: [Invocation] = []
    var launchError: Error?
    var handler: (Invocation) -> CommandResult = { _ in CommandResult(exitCode: 0, stdout: "", stderr: "") }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        let invocation = Invocation(executable: executable, arguments: arguments)
        invocations.append(invocation)
        if let launchError { throw launchError }
        return handler(invocation)
    }
}

final class FakeClamshell: ClamshellStateReading, @unchecked Sendable {
    var lidClosed: Bool? = false
    func isLidClosed() -> Bool? { lidClosed }
}

// MARK: - Session

final class FakeClock: SessionClock, @unchecked Sendable {
    private var current: Date
    init(_ start: Date) { current = start }
    func now() -> Date { current }
    func advance(by seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}

@MainActor
final class ManualTicker: SessionTicker {
    private(set) var isRunning = false
    private var handler: (@MainActor () -> Void)?

    func start(interval: TimeInterval, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        isRunning = true
    }

    func stop() {
        handler = nil
        isRunning = false
    }

    func fire() { handler?() }
}

/// Wires real SessionManager / SleepController / PowerMonitor against fakes at the OS boundary.
@MainActor
final class SessionHarness {
    let clock = FakeClock(Date(timeIntervalSince1970: 1_000_000))
    let power: FakePowerSourceProvider
    let assertions = FakeAssertionProvider()
    let helper = FakeSleepHelper()
    let clamshell = FakeClamshell()
    let ticker = ManualTicker()
    let notificationCenter = NotificationCenter()
    var policy: PowerPolicy
    let monitor: PowerMonitor
    let controller: SleepController
    private(set) var session: SessionManager!

    init(
        policy: PowerPolicy = .default,
        snapshot: PowerSnapshot = PowerSnapshot(isACConnected: true, batteryPercentage: 90, isCharging: true),
        helperInstalled: Bool = true
    ) {
        self.policy = policy
        power = FakePowerSourceProvider(snapshot: snapshot)
        helper.installed = helperInstalled
        monitor = PowerMonitor(provider: power)
        controller = SleepController(assertions: assertions, helper: helper, clamshell: clamshell)
        session = SessionManager(
            sleepController: controller,
            powerMonitor: monitor,
            policyProvider: { [unowned self] in self.policy },
            clock: clock,
            ticker: ticker,
            notificationCenter: notificationCenter
        )
        controller.refreshHelperStatus()
        monitor.start()
    }
}

func onBattery(_ percentage: Int) -> PowerSnapshot {
    PowerSnapshot(isACConnected: false, batteryPercentage: percentage, isCharging: false)
}

func onAC(_ percentage: Int) -> PowerSnapshot {
    PowerSnapshot(isACConnected: true, batteryPercentage: percentage, isCharging: true)
}
