import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship
    var projects: [Project] = []

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class WorkSession: Identifiable {
    @Attribute(.unique) var id: UUID
    var start: Date
    var end: Date?
    // When the session is active (not ended), `lastResume` stores the timestamp
    // when the current active segment started. It's nil when the session is
    // paused. `elapsedBeforePause` accumulates duration from previous segments.
    var lastResume: Date?
    var elapsedBeforePause: TimeInterval = 0

    @Relationship
    var project: Project? = nil

    init(id: UUID = UUID(), start: Date = Date(), end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
        // new sessions start active
        self.lastResume = start
    }

    var duration: TimeInterval {
        // total accumulated time from previous segments
        var total = elapsedBeforePause
        // If currently running, add the active segment time up to now/end
        if let lr = lastResume {
            let endTime = end ?? Date()
            total += endTime.timeIntervalSince(lr)
        }
        return total
    }
}

@Model
final class Project: Identifiable, ObservableObject {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    @Relationship(inverse: \Category.projects)
    var category: Category? = nil
    @Relationship(inverse: \WorkSession.project)
    var sessions: [WorkSession] = []

    init(id: UUID = UUID(), name: String, colorHex: String = "#1E90FF", category: Category? = nil, sessions: [WorkSession] = []) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.category = category
        self.sessions = sessions
    }

    var totalTime: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }
}
