import SwiftUI
import WakeMateCore

final class SheetPresenter: ObservableObject {
    @Published var isShowing = false
}

/// 3-step readiness checklist for Closed-Lid Mode.
public struct ReadinessChecklistView: View {
    @ObservedObject var session: SessionManager
    @ObservedObject var power: PowerMonitor
    @ObservedObject var sleep: SleepController

    @StateObject private var helperSheet = SheetPresenter()

    public init(session: SessionManager, power: PowerMonitor, sleep: SleepController) {
        self.session = session
        self.power = power
        self.sleep = sleep
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Closed-Lid Mode Readiness")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if session.readiness.isReadyToCloseLid {
                    Label("Ready to close lid", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            VStack(spacing: 8) {
                checklistRow(
                    stepNumber: 1,
                    title: "Privileged Helper",
                    subtitle: sleep.isHelperInstalled ? "Authorized via sudoers" : "Required for clamshell sleep prevention",
                    isSatisfied: sleep.isHelperInstalled,
                    actionTitle: sleep.isHelperInstalled ? nil : "Setup Info"
                ) {
                    helperSheet.isShowing = true
                }

                Divider()

                checklistRow(
                    stepNumber: 2,
                    title: "Power & Battery Policy",
                    subtitle: powerSubtitle,
                    isSatisfied: session.readiness.powerOK
                )

                Divider()

                checklistRow(
                    stepNumber: 3,
                    title: "Session Active",
                    subtitle: session.isActive ? "Preventing idle and system sleep" : "Start a session to engage sleep prevention",
                    isSatisfied: session.isActive
                )
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .sheet(isPresented: $helperSheet.isShowing) {
            HelperSetupSheet()
        }
    }

    private var powerSubtitle: String {
        let policy = PowerPolicy.load()
        if let violation = policy.violation(for: power.snapshot) {
            return "Policy violation: \(violation.userDescription)"
        }
        if power.isACConnected {
            return "Connected to AC adapter (Charging/Charged)"
        } else if let pct = power.batteryPercentage {
            return "On battery (\(pct)%) • Above cutoff (\(policy.batteryCutoff)%)"
        } else {
            return "Power conditions satisfied"
        }
    }

    private func checklistRow(
        stepNumber: Int,
        title: String,
        subtitle: String,
        isSatisfied: Bool,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSatisfied ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSatisfied ? Color.green : Color.secondary)
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(stepNumber). \(title)")
                        .font(.system(size: 12, weight: .medium))

                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.link)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }
}

/// Helper Setup Instructions Sheet.
struct HelperSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Privileged Helper Setup", systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("To keep your MacBook awake with the lid closed without Apple Developer ID notarization, WakeMate uses a scoped sudoers rule for pmset and a failsafe watchdog.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Run this command in Terminal:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Text("sudo ./Scripts/install-helper.sh")
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("sudo ./Scripts/install-helper.sh", forType: .string)
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }

            Text("To uninstall at any time: `sudo ./Scripts/uninstall-helper.sh`")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 480)
    }
}
