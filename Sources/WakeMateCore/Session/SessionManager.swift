import Foundation
import Combine
import os

// MARK: - Clock & Ticker Abstractions

public protocol SessionClock: Sendable {
    func now() -> Date
}

public struct SystemClock: SessionClock {
    public init() {}
    public func now() -> Date { Date() }
}

@MainActor
public protocol SessionTicker: AnyObject {
    func start(interval: TimeInterval, handler: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
public final class TimerSessionTicker: SessionTicker {
    private var timer: Timer?

    public init() {}

    public func start(interval: TimeInterval, handler: @escaping @MainActor () -> Void) {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
        // Apple Silicon energy efficiency: coalesce wakeups with system events
        t.tolerance = min(max(interval * 0.1, 0.5), 5.0)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Session Domain Types

public enum SessionDuration: String, CaseIterable, Identifiable, Sendable {
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case twoHours = "2h"
    case fourHours = "4h"
    case indefinite = "Indefinite"

    public var id: String { rawValue }

    public var seconds: TimeInterval? {
        switch self {
        case .thirtyMinutes: return 1800
        case .oneHour: return 3600
        case .twoHours: return 7200
        case .fourHours: return 14400
        case .indefinite: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .indefinite: return "Indefinite"
        }
    }
}

public enum SessionState: Equatable, Sendable {
    case idle
    case active(startedAt: Date, endsAt: Date?, duration: SessionDuration)
}

public enum SessionStopReason: Equatable, Sendable {
    case user
    case timerExpired
    case powerViolation(PowerViolation)
    case appTerminating

    public var userDescription: String {
        switch self {
        case .user: return "Stopped by user"
        case .timerExpired: return "Session timer completed"
        case let .powerViolation(v): return "Power rule violation: \(v.userDescription)"
        case .appTerminating: return "Application quit"
        }
    }
}

public struct ReadinessStatus: Equatable, Sendable {
    public var helperInstalled: Bool
    public var powerOK: Bool
    public var sessionRunning: Bool

    public var isReadyToCloseLid: Bool {
        helperInstalled && powerOK && sessionRunning
    }

    public init(helperInstalled: Bool, powerOK: Bool, sessionRunning: Bool) {
        self.helperInstalled = helperInstalled
        self.powerOK = powerOK
        self.sessionRunning = sessionRunning
    }
}

public enum SessionError: Error, Equatable, LocalizedError, Sendable {
    case powerPolicyViolated(PowerViolation)

    public var errorDescription: String? {
        switch self {
        case let .powerPolicyViolated(v):
            return "Cannot start session: \(v.userDescription)"
        }
    }
}

// MARK: - Session Manager

@MainActor
public final class SessionManager: ObservableObject {
    public static let heartbeatInterval: TimeInterval = 30

    @Published public private(set) var state: SessionState = .idle
    @Published public var selectedDuration: SessionDuration = .oneHour
    @Published public private(set) var remaining: TimeInterval?
    @Published public private(set) var lastStopReason: SessionStopReason?
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var readiness: ReadinessStatus

    public var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    private let sleepController: SleepController
    private let powerMonitor: PowerMonitor
    private let policyProvider: @MainActor () -> PowerPolicy
    private let clock: any SessionClock
    private let ticker: any SessionTicker
    private let notificationCenter: NotificationCenter
    private var powerObserverToken: UUID?
    private var defaultsObserver: NSObjectProtocol?
    private var lastHeartbeatAt: Date
    private let logger = Logger(subsystem: "com.wakemate.app", category: "SessionManager")

    public init(
        sleepController: SleepController,
        powerMonitor: PowerMonitor,
        policyProvider: @escaping @MainActor () -> PowerPolicy = { PowerPolicy.load() },
        clock: any SessionClock,
        ticker: any SessionTicker,
        notificationCenter: NotificationCenter = .default
    ) {
        self.sleepController = sleepController
        self.powerMonitor = powerMonitor
        self.policyProvider = policyProvider
        self.clock = clock
        self.ticker = ticker
        self.notificationCenter = notificationCenter
        self.lastHeartbeatAt = clock.now()

        let initialPowerOK = policyProvider().violation(for: powerMonitor.snapshot) == nil
        self.readiness = ReadinessStatus(
            helperInstalled: sleepController.isHelperInstalled,
            powerOK: initialPowerOK,
            sessionRunning: false
        )

        setupObservations()
    }

    public convenience init(
        sleepController: SleepController,
        powerMonitor: PowerMonitor,
        policyProvider: @escaping @MainActor () -> PowerPolicy = { PowerPolicy.load() },
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            sleepController: sleepController,
            powerMonitor: powerMonitor,
            policyProvider: policyProvider,
            clock: SystemClock(),
            ticker: TimerSessionTicker(),
            notificationCenter: notificationCenter
        )
    }

    private func setupObservations() {
        powerObserverToken = powerMonitor.addObserver { [weak self] snapshot in
            guard let self else { return }
            self.handlePowerChange(snapshot)
        }

        defaultsObserver = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSettingsChange()
            }
        }
    }

    private func updateReadiness() {
        let policy = policyProvider()
        let powerOK = policy.violation(for: powerMonitor.snapshot) == nil
        readiness = ReadinessStatus(
            helperInstalled: sleepController.isHelperInstalled,
            powerOK: powerOK,
            sessionRunning: isActive
        )
    }

    private func handlePowerChange(_ snapshot: PowerSnapshot) {
        let policy = policyProvider()
        if let violation = policy.violation(for: snapshot) {
            if isActive {
                logger.warning("Active session violated power rule: \(violation.userDescription, privacy: .public)")
                teardown(reason: .powerViolation(violation), sleepImmediatelyIfLidClosed: true)
            }
        }
        updateReadiness()
    }

    private func handleSettingsChange() {
        let policy = policyProvider()
        if let violation = policy.violation(for: powerMonitor.snapshot) {
            if isActive {
                logger.warning("Settings change caused power rule violation: \(violation.userDescription, privacy: .public)")
                teardown(reason: .powerViolation(violation), sleepImmediatelyIfLidClosed: true)
            }
        }
        updateReadiness()
    }

    public func start(duration: SessionDuration? = nil) throws {
        lastErrorMessage = nil
        let targetDuration = duration ?? selectedDuration

        let currentPolicy = policyProvider()
        if let violation = currentPolicy.violation(for: powerMonitor.snapshot) {
            let msg = violation.userDescription
            lastErrorMessage = msg
            throw SessionError.powerPolicyViolated(violation)
        }

        let now = clock.now()
        let endsAt = targetDuration.seconds.map { now.addingTimeInterval($0) }

        try sleepController.activate(reason: "WakeMate Session (\(targetDuration.displayName))", until: endsAt)

        state = .active(startedAt: now, endsAt: endsAt, duration: targetDuration)
        remaining = targetDuration.seconds
        lastHeartbeatAt = now

        let tickInterval: TimeInterval = (targetDuration == .indefinite) ? Self.heartbeatInterval : 1.0
        ticker.start(interval: tickInterval) { [weak self] in
            self?.tick()
        }

        updateReadiness()
    }

    public func stop() {
        teardown(reason: .user, sleepImmediatelyIfLidClosed: false)
    }

    public func handleTermination() {
        teardown(reason: .appTerminating, sleepImmediatelyIfLidClosed: false)
    }

    private func tick() {
        guard case let .active(_, endsAt, _) = state else { return }

        let now = clock.now()

        if let endsAt {
            let rem = max(0, endsAt.timeIntervalSince(now))
            remaining = rem
            if rem <= 0 {
                logger.info("Session timer reached zero. Ending session and restoring sleep.")
                teardown(reason: .timerExpired, sleepImmediatelyIfLidClosed: true)
                return
            }
        }

        if now.timeIntervalSince(lastHeartbeatAt) >= Self.heartbeatInterval {
            sleepController.heartbeat()
            lastHeartbeatAt = now
        }
    }

    private func teardown(reason: SessionStopReason, sleepImmediatelyIfLidClosed: Bool) {
        ticker.stop()
        state = .idle
        remaining = nil
        lastStopReason = reason

        sleepController.deactivate(sleepImmediatelyIfLidClosed: sleepImmediatelyIfLidClosed)
        updateReadiness()
    }
}
