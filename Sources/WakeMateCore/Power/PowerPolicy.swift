import Foundation

/// A point-in-time reading of the Mac's power state.
public struct PowerSnapshot: Equatable, Sendable {
    /// `true` when the Mac is drawing power from an adapter.
    public var isACConnected: Bool
    /// Internal battery charge 0–100, or `nil` on Macs without a battery.
    public var batteryPercentage: Int?
    public var isCharging: Bool

    public init(isACConnected: Bool, batteryPercentage: Int?, isCharging: Bool) {
        self.isACConnected = isACConnected
        self.batteryPercentage = batteryPercentage.map { min(max($0, 0), 100) }
        self.isCharging = isCharging
    }

    /// Used before the first IOKit read. Assumes AC so nothing is torn down spuriously.
    public static let unknown = PowerSnapshot(isACConnected: true, batteryPercentage: nil, isCharging: false)
}

/// Why the current power state is not acceptable for an active session.
public enum PowerViolation: Equatable, Sendable {
    case adapterDisconnected
    case batteryAtOrBelowCutoff(percentage: Int, cutoff: Int)

    public var userDescription: String {
        switch self {
        case .adapterDisconnected:
            return "Power adapter disconnected"
        case let .batteryAtOrBelowCutoff(percentage, cutoff):
            return "Battery at \(percentage)% (cutoff \(cutoff)%)"
        }
    }
}

/// `@AppStorage` / `UserDefaults` keys shared by the UI and the core.
public enum SettingsKey {
    public static let requirePowerAdapter = "requirePowerAdapter"
    public static let endOnLowBattery = "endOnLowBattery"
    public static let batteryCutoff = "batteryCutoff"
    public static let showMenuBarTimer = "showMenuBarTimer"
    public static let selectedDuration = "selectedDuration"
}

/// The user's power rules. Pure value type so the decision logic is trivially testable.
public struct PowerPolicy: Equatable, Sendable {
    public static let cutoffRange: ClosedRange<Int> = 10...80
    public static let defaultCutoff = 30
    public static let `default` = PowerPolicy(
        requiresPowerAdapter: false,
        endsOnLowBattery: true,
        batteryCutoff: defaultCutoff
    )

    public var requiresPowerAdapter: Bool
    public var endsOnLowBattery: Bool
    public private(set) var batteryCutoff: Int

    public init(requiresPowerAdapter: Bool, endsOnLowBattery: Bool, batteryCutoff: Int) {
        self.requiresPowerAdapter = requiresPowerAdapter
        self.endsOnLowBattery = endsOnLowBattery
        self.batteryCutoff = min(max(batteryCutoff, Self.cutoffRange.lowerBound), Self.cutoffRange.upperBound)
    }

    /// Returns the first rule the snapshot breaks, or `nil` if a session may run.
    /// The adapter rule wins because it is the stricter, user-explicit requirement.
    public func violation(for snapshot: PowerSnapshot) -> PowerViolation? {
        if requiresPowerAdapter && !snapshot.isACConnected {
            return .adapterDisconnected
        }
        // On AC the battery is not draining, so the low-battery rule is irrelevant.
        if endsOnLowBattery, !snapshot.isACConnected, let percentage = snapshot.batteryPercentage,
           percentage <= batteryCutoff {
            return .batteryAtOrBelowCutoff(percentage: percentage, cutoff: batteryCutoff)
        }
        return nil
    }

    /// Reads the policy written by the Settings UI's `@AppStorage` bindings.
    public static func load(from defaults: UserDefaults = .standard) -> PowerPolicy {
        let requiresAdapter = defaults.object(forKey: SettingsKey.requirePowerAdapter) as? Bool
            ?? Self.default.requiresPowerAdapter
        let endsOnLow = defaults.object(forKey: SettingsKey.endOnLowBattery) as? Bool
            ?? Self.default.endsOnLowBattery
        let cutoff = (defaults.object(forKey: SettingsKey.batteryCutoff) as? NSNumber)?.intValue
            ?? Self.default.batteryCutoff
        return PowerPolicy(requiresPowerAdapter: requiresAdapter, endsOnLowBattery: endsOnLow, batteryCutoff: cutoff)
    }
}
