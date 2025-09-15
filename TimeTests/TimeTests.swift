//
//  TimeTests.swift
//  TimeTests
//
//  Created by Alon Farchy on 9/15/25.
//

import Foundation
import Testing
@testable import Time

struct TimeTests {

    @Test func projectTotalTime() async throws {
        let s1 = WorkSession(start: Date().addingTimeInterval(-3600), end: Date().addingTimeInterval(-1800))
        let s2 = WorkSession(start: Date().addingTimeInterval(-1800), end: Date())
        let p = Project(name: "Test", sessions: [s1, s2])
        #expect(p.totalTime > 0)
    }

    @Test func startAndPauseSession() async throws {
        let p = Project(name: "X")
        let s = WorkSession(start: Date())
        s.project = p
        p.sessions.append(s)
        // simulate some elapsed time
        s.end = s.start.addingTimeInterval(2)
        #expect(s.duration >= 2)
    }

}
