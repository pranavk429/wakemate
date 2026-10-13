import Foundation
import IOKit.ps
import Combine
import os

public enum PowerMonitorError: Error, Equatable, Sendable {
    /// `IOPSNotificationCreateRunLoopSource` returned nil; monitor falls back to polling.
    case notificationRegistrationFailed
}

/// Abstraction over the IOKit power-sources API so `PowerMonitor` can be tested.
@MainActor
public protocol PowerSourceProviding: AnyObject {
    func currentSnapshot() -> PowerSnapshot
    /// Begin delivering change callbacks on the main thread.
    func startObserving(onChange: @escaping @MainActor () -> Void) throws
    func stopObserving()
}

// MARK: - IOKit implementation

/// Reads power state via `IOPSCopyPowerSourcesInfo` and observes changes via
/// `IOPSNotificationCreateRunLoopSource` on the main run loop.
@MainActor
public final class IOKitPowerSourceProvider: PowerSourceProviding {
    /// Heap box whose address is handed to the C callback as its context pointer.
    @MainActor
    private final class CallbackBox {
        let handler: @MainActor () -> Void
        init(handler: @escaping @MainActor () -> Void) { self.handler = handler }
    }

    private var runLoopSource: CFRunLoopSource?
    private var callbackBox: CallbackBox?

    public init() {}

    public func currentSnapshot() -> PowerSnapshot {
        Self.readSnapshot() ?? .unknown
    }

    public func startObserving(onChange: @escaping @MainActor () -> Void) throws {
        stopObserving()
        let box = CallbackBox(handler: onChange)
        let context = Unmanaged.passUnretained(box).toOpaque()

        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().handler()
            }
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            throw PowerMonitorError.notificationRegistrationFailed
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        callbackBox = box
        runLoopSource = source
    }

    public func stopObserving() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        runLoopSource = nil
        callbackBox = nil
    }

    nonisolated static func readSnapshot() -> PowerSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }

        let providingType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        var isAC = providingType == kIOPMACPowerKey
        var batteryPercentage: Int?
        var isCharging = false

        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                batteryPercentage = Int((Double(current) / Double(maximum) * 100).rounded())
            }
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            if let state = description[kIOPSPowerSourceStateKey] as? String {
                isAC = isAC || state == kIOPSACPowerValue
            }
            break
        }

        if batteryPercentage == nil && providingType == nil { isAC = true }
        return PowerSnapshot(isACConnected: isAC, batteryPercentage: batteryPercentage, isCharging: isCharging)
    }
}

// MARK: - Monitor

/// Publishes real-time power state to SwiftUI and subscribers such as `SessionManager`.
@MainActor
public final class PowerMonitor: ObservableObject {
    public static let fallbackPollingInterval: TimeInterval = 30

    @Published public private(set) var snapshot: PowerSnapshot = .unknown
    @Published public private(set) var isUsingFallbackPolling = false
    @Published public private(set) var lastError: PowerMonitorError?

    public var isACConnected: Bool { snapshot.isACConnected }
    public var batteryPercentage: Int? { snapshot.batteryPercentage }
    public var isCharging: Bool { snapshot.isCharging }
    public var hasBattery: Bool { snapshot.batteryPercentage != nil }

    private let provider: any PowerSourceProviding
    private var observers: [UUID: @MainActor (PowerSnapshot) -> Void] = [:]
    private var fallbackTimer: Timer?
    private var isStarted = false
    private let logger = Logger(subsystem: "com.wakemate.app", category: "PowerMonitor")

    public init(provider: any PowerSourceProviding) {
        self.provider = provider
    }

    public convenience init() {
        self.init(provider: IOKitPowerSourceProvider())
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        refresh()
        do {
            try provider.startObserving { [weak self] in self?.refresh() }
            lastError = nil
        } catch {
            let monitorError = (error as? PowerMonitorError) ?? .notificationRegistrationFailed
            lastError = monitorError
            logger.error("Power notifications unavailable (\(String(describing: monitorError), privacy: .public)); polling every \(Self.fallbackPollingInterval)s")
            startFallbackPolling()
        }
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        provider.stopObserving()
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        isUsingFallbackPolling = false
    }

    public func refresh() {
        let latest = provider.currentSnapshot()
        guard latest != snapshot else { return }
        snapshot = latest
        for observer in observers.values { observer(latest) }
    }

    @discardableResult
    public func addObserver(_ handler: @escaping @MainActor (PowerSnapshot) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    public func removeObserver(_ token: UUID) {
        observers[token] = nil
    }

    private func startFallbackPolling() {
        isUsingFallbackPolling = true
        let timer = Timer(timeInterval: Self.fallbackPollingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }
}
