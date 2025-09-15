import Foundation
import SwiftData

class DataMigrationManager {
    static func createModelContainer() -> ModelContainer {
        let schema = Schema([
            Category.self,
            Project.self,
            WorkSession.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            return container
        } catch {
            print("Failed to create ModelContainer with error: \(error)")
            print("Attempting recovery by resetting the data store...")

            // If migration fails, we need to handle it gracefully
            // This is a last resort - normally we'd want to preserve data
            return createFreshContainer()
        }
    }

    private static func createFreshContainer() -> ModelContainer {
        // Clear the existing database file to start fresh
        let url = URL.applicationSupportDirectory.appending(path: "default.store")
        try? FileManager.default.removeItem(at: url)

        let schema = Schema([
            Category.self,
            Project.self,
            WorkSession.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create fresh ModelContainer: \(error)")
        }
    }

    @MainActor
    static func performPostLaunchMigration(context: ModelContext) {
        // Ensure all categories have colors assigned
        let categoryDescriptor = FetchDescriptor<Category>()

        do {
            let categories = try context.fetch(categoryDescriptor)
            var hasChanges = false

            for category in categories {
                if category.colorHex.isEmpty {
                    category.colorHex = Category.randomColorHex()
                    hasChanges = true
                    print("Assigned color \(category.colorHex) to category '\(category.name)'")
                }
            }

            if hasChanges {
                try context.save()
                print("Category color migration completed")
            }
        } catch {
            print("Post-launch migration failed: \(error)")
        }
    }
}