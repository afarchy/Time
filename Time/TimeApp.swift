//
//  TimeApp.swift
//  Time
//
//  Created by Alon Farchy on 9/15/25.
//

import SwiftUI
import SwiftData
import UserNotifications
import ActivityKit

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

                    // Check Live Activity authorization status
                    if #available(iOS 16.1, *) {
                        let authInfo = ActivityAuthorizationInfo()
                        print("Live Activities enabled: \(authInfo.areActivitiesEnabled)")
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
