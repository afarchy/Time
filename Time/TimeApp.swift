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
    var sharedModelContainer: ModelContainer = DataMigrationManager.createModelContainer()

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
