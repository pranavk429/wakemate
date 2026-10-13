import Foundation
import os

// MARK: - Protocol

/// Controls *system* sleep (including clamshell/lid-closed sleep), which an
/// IOPMAssertion alone cannot prevent on battery. Implementations must be
/// safe to call from any thread.
public protocol SleepHelperProtocol: Sendable {
    /// Whether the privileged mechanism is set up and usable without prompting.
    func isInstalled() -> Bool
    /// Disables all system sleep. `deadline` lets failsafes know when it must end.
    func disableSystemSleep(until deadline: Date?) throws
    /// Restores normal system sleep. Must be idempotent.
    func enableSystemSleep() throws
    /// Reads the live kernel setting (source of truth, independent of app state).
    func isSystemSleepDisabled() throws -> Bool
    /// Asks the system to sleep now (used after restoring sleep with the lid closed).
    func sleepNow() throws
    /// Signals liveness to any out-of-process watchdog.
    func heartbeat()
}

public enum SleepHelperError: Error, Equatable, LocalizedError, Sendable {
    /// sudo refused to run without a password: the sudoers rule is missing or wrong.
    case notAuthorized
    case commandFailed(command: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "WakeMate's helper isn't authorized. Run `sudo ./Scripts/install-helper.sh`."
        case let .commandFailed(command, exitCode, stderr):
            let detail = stderr.isEmpty ? "" : ": \(stderr)"
            return "`\(command)` failed (exit \(exitCode))\(detail)"
        }
    }
}

// MARK: - pmset implementation

/// Toggles `pmset -a disablesleep` through a scoped, password-less sudoers rule:
///
///     <user> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
///
/// The argv used here must match that rule byte-for-byte; tests pin it.
public struct PMSetSleepHelper: SleepHelperProtocol {
    static let sudoPath = "/usr/bin/sudo"
    static let pmsetPath = "/usr/bin/pmset"
    static let commandTimeout: TimeInterval = 10

    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func isInstalled() -> Bool {
        // `sudo -n -l <cmd>` exits 0 only if <cmd> is permitted without a password.
        for value in ["1", "0"] {
            let arguments = ["-n", "-l", Self.pmsetPath, "-a", "disablesleep", value]
            guard let result = try? runner.run(Self.sudoPath, arguments: arguments, timeout: Self.commandTimeout),
                  result.exitCode == 0 else {
                return false
            }
        }
        return true
    }

    public func disableSystemSleep(until deadline: Date?) throws {
        try setDisableSleep(true)
    }

    public func enableSystemSleep() throws {
        try setDisableSleep(false)
    }

    public func isSystemSleepDisabled() throws -> Bool {
        let result = try runChecked(Self.pmsetPath, ["-g"])
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.first == "SleepDisabled" {
                return fields.last == "1"
            }
        }
        // pmset omits the key when it has never been set, which means "not disabled".
        return false
    }

    public func sleepNow() throws {
        _ = try runChecked(Self.pmsetPath, ["sleepnow"])
    }

    public func heartbeat() {}

    private func setDisableSleep(_ disabled: Bool) throws {
        _ = try runChecked(Self.sudoPath, ["-n", Self.pmsetPath, "-a", "disablesleep", disabled ? "1" : "0"])
    }

    private func runChecked(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let result = try runner.run(executable, arguments: arguments, timeout: Self.commandTimeout)
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if executable == Self.sudoPath, Self.isAuthorizationFailure(stderr) {
                throw SleepHelperError.notAuthorized
            }
            throw SleepHelperError.commandFailed(
                command: ([executable] + arguments).joined(separator: " "),
                exitCode: result.exitCode,
                stderr: stderr
            )
        }
        return result
    }

    private static func isAuthorizationFailure(_ stderr: String) -> Bool {
        let markers = ["password is required", "a terminal is required", "is not allowed to execute",
                       "may not run sudo", "not in the sudoers"]
        let lowered = stderr.lowercased()
        return markers.contains { lowered.contains($0) }
    }
}

// MARK: - Lease (contract with the root watchdog)

/// Records that WakeMate currently owns a `disablesleep 1` state.
/// Serialized as shell-friendly `key=value` lines read by `wakemate-watchdog.sh`.
public struct SleepLease: Equatable, Sendable {
    public var pid: Int32
    public var expiresAt: Date?
    public var heartbeatAt: Date

    public init(pid: Int32, expiresAt: Date?, heartbeatAt: Date) {
        self.pid = pid
        self.expiresAt = expiresAt.map(Self.wholeSeconds)
        self.heartbeatAt = Self.wholeSeconds(heartbeatAt)
    }

    public func serialized() -> String {
        let expires = expiresAt.map { Int($0.timeIntervalSince1970) } ?? 0
        return "pid=\(pid)\nexpires=\(expires)\nheartbeat=\(Int(heartbeatAt.timeIntervalSince1970))\n"
    }

    public init?(serialized text: String) {
        var values: [String: Int] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let number = Int(parts[1]) else { continue }
            values[String(parts[0])] = number
        }
        guard let pid = values["pid"], let pid32 = Int32(exactly: pid), pid32 > 0,
              let expires = values["expires"], let heartbeat = values["heartbeat"] else {
            return nil
        }
        self.init(
            pid: pid32,
            expiresAt: expires == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(expires)),
            heartbeatAt: Date(timeIntervalSince1970: TimeInterval(heartbeat))
        )
    }

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

public struct SleepLeaseStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/WakeMate/sleep.lease` — the path install-helper.sh hands the watchdog.
    public static func standard() -> SleepLeaseStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return SleepLeaseStore(url: base.appendingPathComponent("WakeMate/sleep.lease"))
    }

    public func read() -> SleepLease? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return SleepLease(serialized: text)
    }

    public func write(_ lease: SleepLease) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lease.serialized().utf8).write(to: url, options: [.atomic])
    }

    public func clear() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return
        }
    }
}

// MARK: - Failsafe decorator

/// Wraps a real helper so that a lease always brackets `disablesleep 1`:
/// written *before* disabling, removed only *after* a successful restore.
/// The lease enables two recovery paths for cases in-process handlers can't cover
/// (SIGKILL, crash, hang): the root watchdog daemon, and launch-time recovery.
public final class FailsafeSleepHelper: SleepHelperProtocol {
    private let inner: any SleepHelperProtocol
    private let leaseStore: SleepLeaseStore
    private let processID: Int32
    private let clock: any SessionClock
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.wakemate.app", category: "Failsafe")

    public init(
        wrapping inner: any SleepHelperProtocol,
        leaseStore: SleepLeaseStore = .standard(),
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        clock: any SessionClock = SystemClock()
    ) {
        self.inner = inner
        self.leaseStore = leaseStore
        self.processID = processID
        self.clock = clock
    }

    public func isInstalled() -> Bool { inner.isInstalled() }

    public func disableSystemSleep(until deadline: Date?) throws {
        try lock.withLock {
            try leaseStore.write(SleepLease(pid: processID, expiresAt: deadline, heartbeatAt: clock.now()))
            do {
                try inner.disableSystemSleep(until: deadline)
            } catch {
                try? leaseStore.clear()
                throw error
            }
        }
    }

    public func enableSystemSleep() throws {
        try lock.withLock {
            try inner.enableSystemSleep()
            do {
                try leaseStore.clear()
            } catch {
                // Sleep IS restored; a leftover lease only causes a harmless no-op restore later.
                logger.error("Restored sleep but could not delete lease: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func isSystemSleepDisabled() throws -> Bool { try inner.isSystemSleepDisabled() }

    public func sleepNow() throws { try inner.sleepNow() }

    public func heartbeat() {
        lock.withLock {
            guard var lease = leaseStore.read() else { return }
            lease.heartbeatAt = clock.now()
            do {
                try leaseStore.write(lease)
            } catch {
                logger.error("Heartbeat write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        inner.heartbeat()
    }

    /// Call once at launch. If a lease survived, the previous run died while sleep was
    /// disabled — restore it. Returns `true` if a recovery restore was performed.
    @discardableResult
    public func recoverAfterUncleanExit() throws -> Bool {
        try lock.withLock {
            guard let stale = leaseStore.read() else { return false }
            logger.warning("Found stale sleep lease from pid \(stale.pid); restoring system sleep")
            try inner.enableSystemSleep()
            try leaseStore.clear()
            return true
        }
    }
}
