import ActivityKit
import Foundation

@available(iOS 16.1, *)
class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<TimerActivityAttributes>?
    private var updateTimer: Timer?
    private var currentSession: WorkSession?
    private var currentProject: Project?

    private init() {}

    func startTimerActivity(for session: WorkSession, project: Project) {
        // End any existing activity first
        endTimerActivity()

        // Store references for periodic updates
        currentSession = session
        currentProject = project

        print("🎯 Starting Live Activity for session: \(session.id)")
        print("- Checking authorization status...")
        let authInfo = ActivityAuthorizationInfo()
        print("- areActivitiesEnabled: \(authInfo.areActivitiesEnabled)")
        print("- frequentPushesEnabled: \(authInfo.frequentPushesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            print("Live Activities are not enabled - user needs to enable in Settings")
            return
        }

        let attributes = TimerActivityAttributes(
            sessionId: session.id.uuidString,
            projectColor: project.colorHex.isEmpty ? "#1E90FF" : project.colorHex
        )

        let contentState = TimerActivityAttributes.ContentState(
            projectName: project.name,
            elapsedTime: session.elapsedBeforePause,
            isRunning: session.lastResume != nil,
            lastUpdateTime: Date(),
            sessionStartTime: session.lastResume, // Use lastResume for current active period
            pausedTime: session.elapsedBeforePause
        )

        print("Attempting to start Live Activity with:")
        print("- Session ID: \(session.id.uuidString)")
        print("- Project: \(project.name)")
        print("- Is Running: \(session.lastResume != nil)")
        print("- elapsedBeforePause: \(session.elapsedBeforePause)")
        print("- lastResume: \(String(describing: session.lastResume))")
        print("- sessionStartTime: \(String(describing: contentState.sessionStartTime))")
        print("- elapsedTime: \(contentState.elapsedTime)")
        print("- isRunning: \(contentState.isRunning)")

        do {
            print("🚀 Attempting to request Live Activity...")
            print("   - Attributes: \(attributes)")
            print("   - Content State: \(contentState)")

            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            print("✅ Successfully started Live Activity for session: \(session.id)")
            print("   - Activity ID: \(currentActivity?.id ?? "unknown")")
            print("   - Activity State: \(String(describing: currentActivity?.activityState))")

            // Start periodic updates if the session is running
            if session.lastResume != nil {
                startPeriodicUpdates()
            }
        } catch {
            print("❌ Failed to start Live Activity: \(error)")
            print("   Error details: \(error.localizedDescription)")
            print("   Error type: \(type(of: error))")

            // Check if it's an unsupportedTarget error specifically
            if error.localizedDescription.contains("unsupportedTarget") {
                print("   → UNSUPPORTED TARGET ERROR:")
                print("   → This means the Widget Extension target is missing or misconfigured")
                print("   → You need to create a Widget Extension target in Xcode")
                print("   → Go to File → New → Target → Widget Extension")
                print("   → Make sure to include Live Activity support")
            } else {
                print("   → Other error type - check Live Activities permission and device support")
            }
        }
    }

    func updateTimerActivity(for session: WorkSession, project: Project) {
        guard let activity = currentActivity else { return }

        // Update stored references
        currentSession = session
        currentProject = project

        let contentState = TimerActivityAttributes.ContentState(
            projectName: project.name,
            elapsedTime: session.elapsedBeforePause,
            isRunning: session.lastResume != nil,
            lastUpdateTime: Date(),
            sessionStartTime: session.lastResume, // Use lastResume for current active period
            pausedTime: session.elapsedBeforePause
        )

        Task {
            await activity.update(
                .init(state: contentState, staleDate: nil)
            )
        }

        // Start or stop periodic updates based on session state
        if session.lastResume != nil {
            startPeriodicUpdates()
        } else {
            stopPeriodicUpdates()
        }
    }

    func endTimerActivity() {
        print("🏁 END TIMER ACTIVITY called")
        guard let activity = currentActivity else {
            print("🏁 No current activity to end")
            return
        }

        print("🏁 Ending activity with ID: \(activity.id)")

        // Stop periodic updates
        stopPeriodicUpdates()

        // Clear stored references
        currentSession = nil
        currentProject = nil

        Task {
            do {
                print("🏁 Attempting to end Live Activity...")
                await activity.end(nil, dismissalPolicy: .immediate)
                print("🏁 ✅ Live Activity ended successfully")
                currentActivity = nil
            } catch {
                print("🏁 ❌ Error ending Live Activity: \(error)")
            }
        }
    }

    func pauseTimerActivity(for session: WorkSession, project: Project) {
        updateTimerActivity(for: session, project: project)
    }

    func resumeTimerActivity(for session: WorkSession, project: Project) {
        updateTimerActivity(for: session, project: project)
    }

    // MARK: - Periodic Updates

    private func startPeriodicUpdates() {
        stopPeriodicUpdates() // Stop any existing timer

        print("🔄 Starting periodic Live Activity updates")
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.performPeriodicUpdate()
        }
    }

    private func stopPeriodicUpdates() {
        print("⏹️ Stopping periodic Live Activity updates")
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func performPeriodicUpdate() {
        guard let session = currentSession,
              let project = currentProject,
              session.lastResume != nil else {
            print("⚠️ Periodic update skipped - no active session")
            stopPeriodicUpdates()
            return
        }

        print("🔄 Performing periodic Live Activity update")
        updateTimerActivity(for: session, project: project)
    }
}

// Extension to make it easier to use with the existing models
extension LiveActivityManager {
    func handleSessionStart(_ session: WorkSession, project: Project) {
        if #available(iOS 16.1, *) {
            startTimerActivity(for: session, project: project)
        }
    }

    func handleSessionPause(_ session: WorkSession, project: Project) {
        if #available(iOS 16.1, *) {
            pauseTimerActivity(for: session, project: project)
        }
    }

    func handleSessionResume(_ session: WorkSession, project: Project) {
        if #available(iOS 16.1, *) {
            resumeTimerActivity(for: session, project: project)
        }
    }

    func handleSessionStop() {
        print("🛑 HANDLE SESSION STOP called")
        if #available(iOS 16.1, *) {
            print("🛑 iOS 16.1+ available, calling endTimerActivity()")
            endTimerActivity()
        } else {
            print("🛑 iOS 16.1+ NOT available, skipping Live Activity end")
        }
    }
}