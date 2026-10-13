import SwiftUI
import WakeMateCore

/// App settings window content, persisted via @AppStorage.
public struct SettingsView: View {
    @AppStorage(SettingsKey.requirePowerAdapter) private var requirePowerAdapter: Bool = false
    @AppStorage(SettingsKey.endOnLowBattery) private var endOnLowBattery: Bool = true
    @AppStorage(SettingsKey.batteryCutoff) private var batteryCutoff: Int = PowerPolicy.defaultCutoff
    @AppStorage(SettingsKey.showMenuBarTimer) private var showMenuBarTimer: Bool = true

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("Require a power adapter", isOn: $requirePowerAdapter)
                    .help("Sessions will only start and continue while connected to an AC power adapter.")

                Text("If enabled, sessions will terminate immediately if the charger is unplugged, allowing your Mac to sleep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Power Adapter Rule")
            }

            Section {
                Toggle("End sessions on low battery", isOn: $endOnLowBattery)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Battery cutoff:")
                        Spacer()
                        Text("\(batteryCutoff)%")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(batteryCutoff) },
                            set: { batteryCutoff = Int($0) }
                        ),
                        in: Double(PowerPolicy.cutoffRange.lowerBound)...Double(PowerPolicy.cutoffRange.upperBound),
                        step: 5
                    )
                    .disabled(!endOnLowBattery)

                    HStack {
                        Text("\(PowerPolicy.cutoffRange.lowerBound)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(PowerPolicy.cutoffRange.upperBound)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)

                Text("When running on battery, sessions terminate when charge drops to or below this cutoff percentage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Battery Protection")
            }

            Section {
                Toggle("Show remaining time in menu bar", isOn: $showMenuBarTimer)
            } header: {
                Text("Display")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 360)
    }
}
