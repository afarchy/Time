import Foundation
import SwiftData

// MARK: - Migration Support
enum SchemaV1 {
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
    final class Project {
        @Attribute(.unique) var id: UUID
        var name: String
        var colorHex: String? // Old projects had color
        @Relationship(inverse: \Category.projects)
        var category: Category? = nil
        @Relationship(inverse: \WorkSession.project)
        var sessions: [WorkSession] = []

        init(id: UUID = UUID(), name: String, colorHex: String? = nil, category: Category? = nil, sessions: [WorkSession] = []) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.category = category
            self.sessions = sessions
        }
    }

    @Model
    final class WorkSession {
        @Attribute(.unique) var id: UUID
        var start: Date
        var end: Date?
        var lastResume: Date?
        var elapsedBeforePause: TimeInterval = 0
        @Relationship
        var project: Project? = nil

        init(id: UUID = UUID(), start: Date = Date(), end: Date? = nil) {
            self.id = id
            self.start = start
            self.end = end
            self.lastResume = start
        }
    }
}

// MARK: - Current Models (V2)
@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    @Relationship
    var projects: [Project] = []

    init(id: UUID = UUID(), name: String, colorHex: String = "") {
        self.id = id
        self.name = name
        self.colorHex = colorHex.isEmpty ? Category.randomColorHex() : colorHex
    }

    static func randomColorHex() -> String {
        let colors = [
            "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FECA57",
            "#FF9FF3", "#54A0FF", "#5F27CD", "#00D2D3", "#FF9F43",
            "#74B9FF", "#A29BFE", "#FD79A8", "#FDCB6E", "#6C5CE7",
            "#E17055", "#81ECEC", "#FAB1A0", "#00B894", "#E84393"
        ]
        return colors.randomElement() ?? "#1E90FF"
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
        // For completed sessions (with end date), return the accumulated working time
        if let _ = end {
            return elapsedBeforePause
        }

        // For ongoing sessions, use the accumulated approach
        var total = elapsedBeforePause
        // If currently running, add the active segment time up to now
        if let lr = lastResume {
            total += Date().timeIntervalSince(lr)
        }
        return total
    }
}

@Model
final class Project: Identifiable, ObservableObject {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship(inverse: \Category.projects)
    var category: Category? = nil
    @Relationship(inverse: \WorkSession.project)
    var sessions: [WorkSession] = []

    init(id: UUID = UUID(), name: String, category: Category? = nil, sessions: [WorkSession] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.sessions = sessions
    }

    var totalTime: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    var colorHex: String {
        category?.colorHex ?? "#1E90FF"
    }
}
