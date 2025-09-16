import ActivityKit
import WidgetKit
import SwiftUI

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            LockScreenTimerView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Circle()
                            .fill(Color(hex: context.attributes.projectColor))
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading) {
                            Text(context.state.projectName)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(context.state.isRunning ? "Running" : "Paused")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerText(for: context.state))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer()
                        Text("Working on \(context.state.projectName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } compactLeading: {
                // Compact leading UI
                Circle()
                    .fill(Color(hex: context.attributes.projectColor))
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                // Compact trailing UI
                Text(compactTimerText(for: context.state))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
            } minimal: {
                // Minimal UI (just the circle)
                Circle()
                    .fill(Color(hex: context.attributes.projectColor))
                    .frame(width: 20, height: 20)
            }
        }
    }

    private func timerText(for state: TimerActivityAttributes.ContentState) -> String {
        let elapsed = calculateCurrentElapsed(state: state)
        return formatTime(from: elapsed)
    }

    private func compactTimerText(for state: TimerActivityAttributes.ContentState) -> String {
        let elapsed = calculateCurrentElapsed(state: state)
        return formatCompactTime(from: elapsed)
    }

    private func calculateCurrentElapsed(state: TimerActivityAttributes.ContentState) -> TimeInterval {
        print("🔍 TimerLiveActivity calculateCurrentElapsed:")
        print("   - isRunning: \(state.isRunning)")
        print("   - sessionStartTime: \(String(describing: state.sessionStartTime))")
        print("   - elapsedTime: \(state.elapsedTime)")

        guard state.isRunning else {
            // Timer is paused: use the stored elapsed time (accumulated from all previous periods)
            print("   - timer paused, returning elapsedTime: \(state.elapsedTime)")
            return state.elapsedTime
        }

        guard let sessionStart = state.sessionStartTime else {
            // Timer says it's running but no start time - fallback to elapsed time
            print("   - ERROR: running but no sessionStartTime, returning elapsedTime: \(state.elapsedTime)")
            return state.elapsedTime
        }

        // Timer is running: return accumulated time + current active period
        // Note: sessionStartTime here is actually lastResume (when current period started)
        let currentSegmentTime = Date().timeIntervalSince(sessionStart)
        let totalTime = state.elapsedTime + currentSegmentTime
        print("   - sessionStart: \(sessionStart)")
        print("   - currentTime: \(Date())")
        print("   - currentSegmentTime: \(currentSegmentTime)")
        print("   - totalTime (elapsedTime + currentSegmentTime): \(state.elapsedTime) + \(currentSegmentTime) = \(totalTime)")
        return totalTime
    }
}

struct LockScreenTimerView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(hex: context.attributes.projectColor))
                    .frame(width: 16, height: 16)
                Text(context.state.projectName)
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
                Text(context.state.isRunning ? "⏵" : "⏸")
                    .font(.title2)
            }

            HStack {
                Text(timerText(for: context.state))
                    .font(.title)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Spacer()
                VStack(alignment: .trailing) {
                    Text(context.state.isRunning ? "Running" : "Paused")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Last updated: \(context.state.lastUpdateTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func timerText(for state: TimerActivityAttributes.ContentState) -> String {
        if state.isRunning, let sessionStart = state.sessionStartTime {
            // Timer is running: calculate current elapsed time
            let currentSessionTime = Date().timeIntervalSince(sessionStart)
            let totalElapsed = state.pausedTime + currentSessionTime
            return formatTime(from: totalElapsed)
        } else {
            // Timer is paused: use the stored elapsed time
            return formatTime(from: state.elapsedTime)
        }
    }
}

// Extension to support hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Helper functions for time formatting
private func formatTime(from interval: TimeInterval) -> String {
    let hours = Int(interval) / 3600
    let minutes = Int(interval) % 3600 / 60
    let seconds = Int(interval) % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private func formatCompactTime(from interval: TimeInterval) -> String {
    let hours = Int(interval) / 3600
    let minutes = Int(interval) % 3600 / 60

    if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else {
        return "\(minutes)m"
    }
}