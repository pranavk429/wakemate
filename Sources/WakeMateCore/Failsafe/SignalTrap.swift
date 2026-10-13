import Foundation
import os

/// Traps SIGTERM and SIGINT to run emergency cleanup before exiting.
public final class SignalTrap: @unchecked Sendable {
    private var termSource: DispatchSourceSignal?
    private var intSource: DispatchSourceSignal?
    private let logger = Logger(subsystem: "com.wakemate.app", category: "SignalTrap")

    public init() {}

    /// Installs signal handlers for SIGTERM and SIGINT.
    /// Runs `cleanup` on the main queue and then calls `exit(0)`.
    public func install(cleanup: @escaping @MainActor () -> Void) {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { [weak self] in
            self?.logger.warning("Received SIGTERM. Executing emergency sleep restoration...")
            MainActor.assumeIsolated {
                cleanup()
            }
            exit(0)
        }
        term.resume()
        termSource = term

        let int = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        int.setEventHandler { [weak self] in
            self?.logger.warning("Received SIGINT. Executing emergency sleep restoration...")
            MainActor.assumeIsolated {
                cleanup()
            }
            exit(0)
        }
        int.resume()
        intSource = int
    }
}
