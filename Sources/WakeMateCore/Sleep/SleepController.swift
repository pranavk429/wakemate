import Foundation
import IOKit.pwr_mgt
import Combine
import os

// MARK: - Power Assertion Abstraction

public struct PowerAssertionHandle: Hashable, Sendable {
    public let rawValue: IOPMAssertionID

    public init(rawValue: IOPMAssertionID) {
        self.rawValue = rawValue
    }
}

public protocol PowerAssertionProviding: Sendable {
    func createPreventIdleSleepAssertion(reason: String) throws -> PowerAssertionHandle
    func release(_ handle: PowerAssertionHandle) throws
}

public enum SleepControllerError: Error, Equatable, LocalizedError, Sendable {
    case assertionCreationFailed(code: IOReturn)
    case assertionReleaseFailed(code: IOReturn)

    public var errorDescription: String? {
        switch self {
        case let .assertionCreationFailed(code):
            return "Failed to create power assertion (IOReturn \(code))"
        case let .assertionReleaseFailed(code):
            return "Failed to release power assertion (IOReturn \(code))"
        }
    }
}

public final class IOPMAssertionProvider: PowerAssertionProviding {
    public init() {}

    public func createPreventIdleSleepAssertion(reason: String) throws -> PowerAssertionHandle {
        var assertionID: IOPMAssertionID = 0
        let ret = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        guard ret == kIOReturnSuccess else {
            throw SleepControllerError.assertionCreationFailed(code: ret)
        }
        return PowerAssertionHandle(rawValue: assertionID)
    }

    public func release(_ handle: PowerAssertionHandle) throws {
        let ret = IOPMAssertionRelease(handle.rawValue)
        guard ret == kIOReturnSuccess else {
            throw SleepControllerError.assertionReleaseFailed(code: ret)
        }
    }
}

// MARK: - Clamshell State Reading

public protocol ClamshellStateReading: Sendable {
    func isLidClosed() -> Bool?
}

public struct IOKitClamshellReader: ClamshellStateReading {
    public init() {}

    public func isLidClosed() -> Bool? {
        let matching = IOServiceMatching("IOPMrootDomain")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        if let prop = IORegistryEntryCreateCFProperty(service, "AppleClamshellClosed" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
            if let b = prop as? Bool { return b }
            if let n = prop as? NSNumber { return n.boolValue }
        }
        return nil
    }
}

// MARK: - Sleep Controller

/// Coordinates open-lid assertion (`IOPMAssertionCreateWithName`) and
/// closed-lid system sleep prevention (`SleepHelperProtocol`).
@MainActor
public final class SleepController: ObservableObject {
    @Published public private(set) var isPreventingIdleSleep: Bool = false
    @Published public private(set) var isPreventingClamshellSleep: Bool = false
    @Published public private(set) var isHelperInstalled: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    private let assertions: any PowerAssertionProviding
    private let helper: any SleepHelperProtocol
    private let clamshell: any ClamshellStateReading
    private var activeAssertionHandle: PowerAssertionHandle?
    private let logger = Logger(subsystem: "com.wakemate.app", category: "SleepController")

    public init(
        assertions: any PowerAssertionProviding = IOPMAssertionProvider(),
        helper: any SleepHelperProtocol = FailsafeSleepHelper(wrapping: PMSetSleepHelper()),
        clamshell: any ClamshellStateReading = IOKitClamshellReader()
    ) {
        self.assertions = assertions
        self.helper = helper
        self.clamshell = clamshell
        refreshHelperStatus()
    }

    public func refreshHelperStatus() {
        isHelperInstalled = helper.isInstalled()
    }

    public func activate(reason: String, until deadline: Date?) throws {
        lastErrorMessage = nil

        // 1. Open-lid assertion
        if activeAssertionHandle == nil {
            let handle = try assertions.createPreventIdleSleepAssertion(reason: reason)
            activeAssertionHandle = handle
            isPreventingIdleSleep = true
        }

        // 2. Closed-lid (clamshell) prevention via helper
        if helper.isInstalled() {
            do {
                try helper.disableSystemSleep(until: deadline)
                isPreventingClamshellSleep = true
                isHelperInstalled = true
            } catch {
                isPreventingClamshellSleep = false
                let msg = "Closed-lid prevention failed: \(error.localizedDescription)"
                lastErrorMessage = msg
                logger.error("\(msg, privacy: .public)")
            }
        } else {
            isPreventingClamshellSleep = false
            isHelperInstalled = false
        }
    }

    @discardableResult
    public func deactivate(sleepImmediatelyIfLidClosed: Bool = true) -> [Error] {
        var errors: [Error] = []

        if isPreventingClamshellSleep {
            var restored = false
            do {
                try helper.enableSystemSleep()
                restored = true
                isPreventingClamshellSleep = false
            } catch {
                logger.error("Failed restoring system sleep, retrying once: \(error.localizedDescription, privacy: .public)")
                do {
                    try helper.enableSystemSleep()
                    restored = true
                    isPreventingClamshellSleep = false
                } catch let retryError {
                    errors.append(retryError)
                    logger.error("Retry failed: \(retryError.localizedDescription, privacy: .public)")
                    lastErrorMessage = "Failed restoring system sleep: \(retryError.localizedDescription)"
                }
            }

            if restored && sleepImmediatelyIfLidClosed {
                if clamshell.isLidClosed() == true {
                    do {
                        try helper.sleepNow()
                    } catch {
                        logger.error("sleepNow failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        if let handle = activeAssertionHandle {
            do {
                try assertions.release(handle)
            } catch {
                errors.append(error)
                logger.error("Failed releasing assertion: \(error.localizedDescription, privacy: .public)")
            }
            activeAssertionHandle = nil
            isPreventingIdleSleep = false
        }

        return errors
    }

    public func heartbeat() {
        if isPreventingClamshellSleep {
            helper.heartbeat()
        }
    }
}
