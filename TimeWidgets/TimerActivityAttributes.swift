import ActivityKit
import Foundation

struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic properties that change during the Live Activity
        var projectName: String
        var elapsedTime: TimeInterval
        var isRunning: Bool
        var lastUpdateTime: Date
        
        // For calculating real-time updates when running
        var sessionStartTime: Date?
        var pausedTime: TimeInterval // Total time paused so far
    }
    
    // Static properties that don't change during the Live Activity
    var sessionId: String
    var projectColor: String
}