import SwiftUI
import WakeMateCore

/// Menu bar icon with active indicator and optional countdown timer.
public struct MenuBarLabelView: View {
    @ObservedObject var session: SessionManager
    @AppStorage(SettingsKey.showMenuBarTimer) private var showTimer: Bool = true

    public init(session: SessionManager) {
        self.session = session
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)

            if session.isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                if showTimer, let remaining = session.remaining {
                    Text(formatCountdown(remaining))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
    }

    private var iconName: String {
        if session.isActive {
            return "bolt.shield.fill"
        } else {
            return "bolt.shield"
        }
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
