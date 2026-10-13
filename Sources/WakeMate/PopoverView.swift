import SwiftUI
import WakeMateCore

/// Main popover view rendered in MenuBarExtra(.window).
public struct PopoverView: View {
    @ObservedObject var session: SessionManager
    @ObservedObject var power: PowerMonitor
    @ObservedObject var sleep: SleepController

    public init(session: SessionManager, power: PowerMonitor, sleep: SleepController) {
        self.session = session
        self.power = power
        self.sleep = sleep
    }

    public var body: some View {
        VStack(spacing: 16) {
            headerBar
            sessionStatusCard
            durationSelectorSection
            actionButton

            if let errorMsg = session.lastErrorMessage {
                errorBanner(errorMsg)
            } else if let stopReason = session.lastStopReason, !session.isActive {
                infoBanner(stopReason.userDescription)
            }

            ReadinessChecklistView(session: session, power: power, sleep: sleep)

            Divider()

            footerBar
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "bolt.shield.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 16, weight: .bold))

                Text("WakeMate")
                    .font(.system(size: 14, weight: .bold))
            }

            Spacer()

            HStack(spacing: 4) {
                if power.isACConnected {
                    Image(systemName: "powerplug.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if let pct = power.batteryPercentage {
                    Image(systemName: batteryIconName(for: pct, isCharging: power.isCharging))
                        .font(.caption)
                        .foregroundStyle(pct <= 20 ? .red : .primary)
                    Text("\(pct)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        }
    }

    private var sessionStatusCard: some View {
        VStack(spacing: 8) {
            if session.isActive {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("ACTIVE SESSION")
                        .font(.caption2)
                        .fontWeight(.heavy)
                        .foregroundStyle(.green)
                        .tracking(0.5)
                    Spacer()
                    Text(session.selectedDuration.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let remaining = session.remaining {
                    Text(formatRemaining(remaining))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                } else {
                    Text("Indefinite")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Text(sleep.isPreventingClamshellSleep ? "Open-lid & closed-lid sleep prevented" : "Open-lid sleep prevented")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Image(systemName: "moon.stars")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Sleep Enabled")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Mac will sleep normally according to system settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(session.isActive ? Color.green.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(session.isActive ? Color.green.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var durationSelectorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session Duration")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Picker("Duration", selection: $session.selectedDuration) {
                ForEach(SessionDuration.allCases) { duration in
                    Text(duration.rawValue).tag(duration)
                }
            }
            .pickerStyle(.segmented)
            .disabled(session.isActive)
        }
    }

    private var actionButton: some View {
        Button(action: toggleSession) {
            HStack {
                Image(systemName: session.isActive ? "stop.fill" : "play.fill")
                Text(session.isActive ? "Stop WakeMate" : "Keep Mac Awake")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(session.isActive ? .red : .blue)
        .controlSize(.large)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .padding(.top, 2)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private func infoBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.top, 2)
            Text("Last session: \(message)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(6)
    }

    private var footerBar: some View {
        HStack {
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }) {
                Label("Settings…", systemImage: "gear")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            Button(action: {
                session.handleTermination()
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Helpers

    private func toggleSession() {
        if session.isActive {
            session.stop()
        } else {
            do {
                try session.start()
            } catch {
                // Handled in session.lastErrorMessage
            }
        }
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    private func batteryIconName(for pct: Int, isCharging: Bool) -> String {
        if isCharging { return "battery.100.bolt" }
        switch pct {
        case 0...20: return "battery.25"
        case 21...50: return "battery.50"
        case 51...75: return "battery.75"
        default: return "battery.100"
        }
    }
}
