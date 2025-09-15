//
//  TimeApp.swift
//  Time
//
//  Created by Alon Farchy on 9/15/25.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct TimeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Project.self,
            Category.self,
            WorkSession.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onAppear {
                    // request local notification permission for background reminders
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        if let error = error {
                            print("Notification auth error: \(error)")
                        } else {
                            print("Notification permission granted: \(granted)")
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
