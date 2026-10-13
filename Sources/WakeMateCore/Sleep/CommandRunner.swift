import Foundation

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum CommandError: Error, Equatable, LocalizedError, Sendable {
    case launchFailed(executable: String, reason: String)
    case timedOut(executable: String, after: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(executable, reason):
            return "Could not launch \(executable): \(reason)"
        case let .timedOut(executable, after):
            return "\(executable) did not finish within \(Int(after))s"
        }
    }
}

/// Runs an executable synchronously. Abstracted so privileged commands are never run in tests.
public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult
}

/// `Process`-based runner. Drains stdout/stderr concurrently so a chatty child can't
/// deadlock on a full pipe, and kills the child if it exceeds `timeout`.
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(executable: executable, reason: error.localizedDescription)
        }

        let stdoutData = PipeDrain(stdoutPipe.fileHandleForReading)
        let stderrData = PipeDrain(stderrPipe.fileHandleForReading)

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            throw CommandError.timedOut(executable: executable, after: timeout)
        }

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdoutData.finish(),
            stderr: stderrData.finish()
        )
    }
}

/// Reads a pipe to EOF on a background queue.
private final class PipeDrain: @unchecked Sendable {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var data = Data()

    init(_ handle: FileHandle) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let bytes = handle.readDataToEndOfFile()
            lock.withLock { data = bytes }
            group.leave()
        }
    }

    func finish() -> String {
        _ = group.wait(timeout: .now() + 2)
        return lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}
