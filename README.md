# Time — simple iOS time tracker

This is a small SwiftUI + SwiftData app that tracks time for projects.

Core features implemented:
- Projects list with color and optional category
- Add and edit projects (name, color, category)
- Category manager (add/delete categories)
- Project detail view with start/pause/stop timer and a list of work sessions
- Sessions are stored in SwiftData models (`Project`, `WorkSession`, `Category`)

Run
---
Open the `Time.xcodeproj` in Xcode (or workspace) and run on a simulator or device.

Notes and next steps
---
- Background tracking and notifications are not implemented. To track while the app is suspended you'll need background tasks and possibly an API to continue timing reliably.
- Sync (iCloud/CloudKit) can be added by moving to CloudKit-backed storage or using NSPersistentCloudKitContainer patterns.
- UX polish: session editing, duration rounding, and nicer UI layout.
