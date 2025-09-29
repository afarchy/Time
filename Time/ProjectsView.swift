import SwiftUI
import SwiftData
import UserNotifications
import ActivityKit

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Project.name)]) private var projects: [Project]

    // Explicit no-argument initializer to avoid synthesized-memberwise access issues
    init() {}

    @State private var showingAdd = false
    @State private var editProject: Project?

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(projects) { project in
                    ProjectRowView(project: project) {
                        editProject = project
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: { showingAdd = true }) {
                        Label("Add Project", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddProjectView()
                    .environment(\.modelContext, modelContext)
            }
            .sheet(item: $editProject) { p in
                ProjectEditView(project: p)
                    .environment(\.modelContext, modelContext)
            }
        } detail: {
            Text("Select a project")
        }
    }

    private func delete(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(projects[index])
            }
        }
    }
}

struct AddProjectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Category.name)]) private var existingCategories: [Category]

    @State private var name = "New Project"
    @State private var categoryName = ""
    @State private var selectedCategory: Category? = nil
    @State private var showingCategoryPicker = false

    var body: some View {
        NavigationView {
            Form {
                TextField("Name", text: $name)

                // Category selection
                if existingCategories.isEmpty {
                    TextField("Category", text: $categoryName)
                } else {
                    HStack {
                        Text((selectedCategory?.name ?? (categoryName.isEmpty ? "Select or enter category" : categoryName)))
                            .foregroundColor(selectedCategory?.name != nil || !categoryName.isEmpty ? .primary : .secondary)
                        Spacer()
                        Button("Choose") {
                            showingCategoryPicker = true
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingCategoryPicker = true
                    }

                    if selectedCategory == nil && !categoryName.isEmpty {
                        Text("New category: \(categoryName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Add Project")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        var cat: Category? = selectedCategory

                        // If no category is selected but we have a name, create/find category
                        if cat == nil && !categoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                            let descriptor = FetchDescriptor<Category>(
                                predicate: #Predicate<Category> { category in
                                    category.name == categoryName
                                }
                            )
                            let existingCategories = try? modelContext.fetch(descriptor)
                            if let existing = existingCategories?.first {
                                cat = existing
                            } else {
                                cat = Category(name: categoryName)
                                modelContext.insert(cat!)
                            }
                        }

                        let p = Project(name: name, category: cat)
                        modelContext.insert(p)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerView(
                    categories: existingCategories,
                    selectedCategory: $selectedCategory,
                    customCategoryName: $categoryName
                )
            }
        }
    }
}

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var project: Project
    @Environment(\.scenePhase) private var scenePhase
    @State private var runningSession: WorkSession?
    @State private var showingConfirmDelete: WorkSession?
    @State private var showingLogPastSession = false
    @State private var showingStartInPast = false
    @State private var showingEditProject = false

    var body: some View {
        // Use TimelineView at the top level to ensure all duration calculations that depend
        // on the current time are recomputed periodically.
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let now = context.date

            // Precompute values outside of the ViewBuilder's returned views.
            let total = project.sessions.reduce(0.0) { acc, s in
                acc + sessionDuration(s, now: now)
            }

            // Prefer the in-memory `runningSession` if present, otherwise detect
            // any open (not-ended) session on the project. This ensures the UI
            // reflects a paused-but-open session even if `runningSession` wasn't
            // yet populated (for example after view re-appear).
            let existingOpen = runningSession ?? project.sessions.first(where: { $0.end == nil })
            let runningIsPaused = existingOpen?.lastResume == nil
            let runningDisplayDur: TimeInterval? = {
                guard let running = existingOpen else { return nil }
                if running.lastResume == nil {
                    return running.elapsedBeforePause
                } else if let lr = running.lastResume {
                    return running.elapsedBeforePause + now.timeIntervalSince(lr)
                } else {
                    return running.elapsedBeforePause
                }
            }()

            let buttonTitle: String = {
                if existingOpen == nil { return "Start" }
                return runningIsPaused ? "Resume" : "Pause"
            }()

            VStack {
                HStack {
                    Spacer()
                    Text(DurationFormatter.string(from: total))
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding()

                if let _ = existingOpen {
                    VStack {
                        Text(DurationFormatter.string(from: runningDisplayDur ?? 0))
                            .font(.title)
                        if runningIsPaused {
                            Text("Paused").font(.caption)
                        }
                    }
                } else {
                    Text("Not running")
                        .font(.title)
                }

                HStack {
                    Button(action: startOrPause) {
                        Text(buttonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: stop) {
                        Text("Stop")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    // Stop should be enabled when we have a session (active or paused)
                    .disabled(runningSession == nil)
                }

                Button(action: { showingLogPastSession = true }) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Log Past Session")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                Button(action: { showingStartInPast = true }) {
                    HStack {
                        Image(systemName: "clock.badge.exclamationmark")
                        Text("Start From Past")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .disabled(runningSession != nil) // Don't allow starting from past if already running

                List {
                    ForEach(project.sessions.sorted(by: { $0.start > $1.start })) { session in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(session.start, style: .date)
                                Text(session.start, style: .time)
                            }
                            Spacer()
                            Text(DurationFormatter.string(from: sessionDuration(session, now: now)))
                        }
                    }
                    .onDelete { idx in
                        if let first = idx.first {
                            let sess = project.sessions.sorted(by: { $0.start > $1.start })[first]
                            showingConfirmDelete = sess
                        }
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingEditProject = true
                }
            }
        }
        .confirmationDialog("Delete session?", isPresented: Binding(get: { showingConfirmDelete != nil }, set: { if !$0 { showingConfirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let s = showingConfirmDelete {
                    cancelRunningNotifications(for: s)
                    modelContext.delete(s)
                    showingConfirmDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            // find a running session (no end)
            runningSession = project.sessions.first(where: { $0.end == nil })

            // Safety check: if there's a session but it's paused, ensure notifications are cancelled
            if let session = runningSession, session.lastResume == nil {
                cancelRunningNotifications(for: session)
            }

            // Clean up any orphaned notifications
            cleanupOrphanedNotifications()

            // Also clean up any stale timer notifications globally
            cleanupAllTimerNotifications()
        }
        .onChange(of: scenePhase) { old, new in
            if new == .active {
                // app became active — refresh running session
                runningSession = project.sessions.first(where: { $0.end == nil })

                // Safety check: if there's a session but it's paused, ensure notifications are cancelled
                if let session = runningSession, session.lastResume == nil {
                    cancelRunningNotifications(for: session)
                }
            }
        }
        .sheet(isPresented: $showingLogPastSession) {
            LogPastSessionView(project: project)
                .environment(\.modelContext, modelContext)
        }
        .sheet(isPresented: $showingStartInPast) {
            StartInPastView(project: project)
                .environment(\.modelContext, modelContext)
        }
        .sheet(isPresented: $showingEditProject) {
            ProjectEditView(project: project)
                .environment(\.modelContext, modelContext)
        }
    }

    private func startOrPause() {
        if let running = runningSession {
            // Check if this session is currently paused (lastResume == nil) or active
            if running.lastResume == nil {
                // Session is paused, so resume it
                running.lastResume = Date()
                do { try modelContext.save() } catch { print("Error saving resume: \(error)") }
                scheduleRunningNotification(for: running)
                LiveActivityManager.shared.handleSessionResume(running, project: project)
            } else {
                // Session is active, so pause it
                running.elapsedBeforePause += Date().timeIntervalSince(running.lastResume!)
                running.lastResume = nil
                do { try modelContext.save() } catch { print("Error saving pause: \(error)") }
                // cancel notifications while paused
                cancelRunningNotifications(for: running)
                LiveActivityManager.shared.handleSessionPause(running, project: project)
            }
        } else {
            // No running session - either start new or resume existing paused session
            // If there's an existing session that's not ended, resume it.
            if let other = project.sessions.first(where: { $0.end == nil }) {
                // resume existing paused session
                other.lastResume = Date()
                runningSession = other
                do { try modelContext.save() } catch { print("Error saving resume: \(error)") }
                scheduleRunningNotification(for: other)
                LiveActivityManager.shared.handleSessionResume(other, project: project)
                return
            }
            // otherwise create a new session
            let s = WorkSession(start: Date())
            s.project = project
            modelContext.insert(s)
            runningSession = s
            do { try modelContext.save() } catch { print("Error saving start: \(error)") }
            scheduleRunningNotification(for: s)
            LiveActivityManager.shared.handleSessionStart(s, project: project)
        }
    }

    private func stop() {
        if let running = runningSession {
            // finalize the session: accumulate any active segment and set end
            if let lr = running.lastResume {
                running.elapsedBeforePause += Date().timeIntervalSince(lr)
            }
            // Important: clear lastResume to indicate session is stopped, not just paused
            running.lastResume = nil
            running.end = Date()
            runningSession = nil
            do { try modelContext.save() } catch { print("Error saving stop: \(error)") }
            cancelRunningNotifications(for: running)
            LiveActivityManager.shared.handleSessionStop()
        }
    }

    // Helper function to calculate session duration respecting pause state
    private func sessionDuration(_ session: WorkSession, now: Date) -> TimeInterval {
        // Use the corrected duration property from the model
        return session.duration
    }


    // Schedule hourly chime notifications at the top of each hour while a session is running
    private func scheduleRunningNotification(for session: WorkSession) {
        let center = UNUserNotificationCenter.current()

        // Cancel any existing notifications for this session first
        cancelRunningNotifications(for: session)

        // Schedule notifications for the next 24 hours at the top of each hour
        let calendar = Calendar.current
        let now = Date()

        for hour in 0..<24 {
            guard let nextHour = calendar.date(byAdding: .hour, value: hour, to: now) else { continue }

            // Get the start of this hour (e.g., 2:35 PM becomes 3:00 PM for next hour)
            let startOfHour = calendar.dateInterval(of: .hour, for: nextHour)?.start ?? nextHour

            // Only schedule if this hour boundary is in the future
            guard startOfHour > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Hourly Time Reminder"
            content.body = "🕐 Working on \(project.name) - \(calendar.component(.hour, from: startOfHour)):00"
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.hour, .minute], from: startOfHour),
                repeats: false
            )

            let identifier = "\(session.id.uuidString)-hour-\(hour)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            center.add(request) { error in
                if let error = error {
                    print("Schedule hourly notification error: \(error)")
                }
            }
        }
    }

    private func cancelRunningNotifications(for session: WorkSession) {
        let center = UNUserNotificationCenter.current()

        // Cancel all hourly notifications for this session
        var identifiers = [session.id.uuidString] // Legacy identifier
        for hour in 0..<24 {
            identifiers.append("\(session.id.uuidString)-hour-\(hour)")
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        // Also cancel any delivered notifications for this session
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // Clean up any orphaned notifications for sessions that shouldn't have them
    private func cleanupOrphanedNotifications() {
        let center = UNUserNotificationCenter.current()

        // Get all pending notifications
        center.getPendingNotificationRequests { requests in
            let sessionBasedRequests = requests.filter { $0.identifier.contains("-hour-") || $0.identifier.count == 36 } // UUID length
            var identifiersToRemove: [String] = []

            for request in sessionBasedRequests {
                let sessionIdString = request.identifier.components(separatedBy: "-hour-").first ?? request.identifier

                // Check if this session should have notifications
                if let sessionId = UUID(uuidString: sessionIdString),
                   let session = project.sessions.first(where: { $0.id == sessionId }) {

                    // Cancel notifications for sessions that are ended or paused
                    if session.end != nil || session.lastResume == nil {
                        identifiersToRemove.append(request.identifier)
                    }
                } else {
                    // Cancel notifications for sessions that no longer exist
                    identifiersToRemove.append(request.identifier)
                }
            }

            // If there's no running session, cancel ALL timer notifications
            if runningSession == nil {
                let allTimerNotifications = requests.filter {
                    $0.content.title.contains("Hourly Time Reminder") ||
                    $0.identifier.contains("-hour-") ||
                    $0.identifier.count == 36 // UUID format
                }
                identifiersToRemove.append(contentsOf: allTimerNotifications.map { $0.identifier })
            }

            if !identifiersToRemove.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
                center.removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
            }
        }
    }

    // Clean up ALL timer notifications globally when no session is running
    private func cleanupAllTimerNotifications() {
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { requests in
            let timerNotifications = requests.filter {
                $0.content.title.contains("Hourly Time Reminder") ||
                $0.content.body.contains("Working on") ||
                $0.identifier.contains("-hour-")
            }

            let identifiers = timerNotifications.map { $0.identifier }
            if !identifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
                center.removeDeliveredNotifications(withIdentifiers: identifiers)
            }
        }
    }

    private var totalTimeString: String {
        DurationFormatter.string(from: project.totalTime)
    }

    private func runningDurationString(from session: WorkSession) -> String {
        DurationFormatter.string(from: session.duration)
    }
}

struct CategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    @Binding var selectedCategory: Category?
    @Binding var customCategoryName: String

    @State private var newCategoryName = ""
    @State private var showingAddNew = false

    var body: some View {
        NavigationView {
            List {
                if !categories.isEmpty {
                    Section("Existing Categories") {
                        ForEach(categories) { category in
                            HStack {
                                Text(category.name)
                                Spacer()
                                if selectedCategory?.id == category.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedCategory = category
                                customCategoryName = ""
                                dismiss()
                            }
                        }
                    }
                }

                Section("Create New Category") {
                    HStack {
                        TextField("New category name", text: $newCategoryName)
                        Button("Add") {
                            if !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                                selectedCategory = nil
                                customCategoryName = newCategoryName.trimmingCharacters(in: .whitespaces)
                                dismiss()
                            }
                        }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !categories.isEmpty {
                    Section {
                        Button("No Category") {
                            selectedCategory = nil
                            customCategoryName = ""
                            dismiss()
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DurationFormatter {
    static func string(from interval: TimeInterval) -> String {
        let ti = Int(interval)
        let h = ti / 3600
        let m = (ti % 3600) / 60
        let s = ti % 60
        if h > 0 {
            return String(format: "%dh %02dm %02ds", h, m, s)
        } else if m > 0 {
            return String(format: "%dm %02ds", m, s)
        } else {
            return String(format: "%ds", s)
        }
    }
}

// small Color helpers
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 30, 144, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    func toHex() -> String? {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return nil
        #endif
    }
}

// MARK: - Category management
struct CategoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Category.name)]) private var categories: [Category]
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""

    var body: some View {
        NavigationView {
            List {
                ForEach(categories) { c in
                    Text(c.name)
                }
                .onDelete { idx in
                    withAnimation {
                        for i in idx { modelContext.delete(categories[i]) }
                    }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        TextField("New category", text: $newName)
                        Button("Add") {
                            let c = Category(name: newName)
                            modelContext.insert(c)
                            newName = ""
                        }
                    }
                }
            }
        }
    }
}

// Project list row that updates its displayed total periodically.
struct ProjectRowView: View {
    @ObservedObject var project: Project
    var onEdit: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let now = context.date
            // compute total using up-to-date 'now' for any running sessions, respecting pause state
            let total = project.sessions.reduce(0.0) { acc, s in
                acc + sessionDuration(s, now: now)
            }

            HStack {
                NavigationLink(value: project) {
                    HStack {
                        Circle()
                            .fill(Color(hex: project.colorHex))
                            .frame(width: 16, height: 16)
                        VStack(alignment: .leading) {
                            Text(project.name)
                                .font(.headline)
                            if let cat = project.category {
                                Text(cat.name).font(.caption)
                            }
                        }
                    }
                }
                Spacer()
                Text(DurationFormatter.string(from: total))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // Helper function to calculate session duration respecting pause state
    private func sessionDuration(_ session: WorkSession, now: Date) -> TimeInterval {
        // Use the corrected duration property from the model
        return session.duration
    }
}

// MARK: - Project editing
struct ProjectEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var project: Project
    @Query(sort: [SortDescriptor(\Category.name)]) private var existingCategories: [Category]

    @State private var name: String = ""
    @State private var categoryName: String = ""
    @State private var selectedCategory: Category? = nil
    @State private var showingCategoryPicker = false

    var body: some View {
        NavigationView {
            Form {
                TextField("Name", text: $name)

                // Category selection
                if existingCategories.isEmpty {
                    TextField("Category", text: $categoryName)
                } else {
                    HStack {
                        Text((selectedCategory?.name ?? (categoryName.isEmpty ? "Select or enter category" : categoryName)))
                            .foregroundColor(selectedCategory?.name != nil || !categoryName.isEmpty ? .primary : .secondary)
                        Spacer()
                        Button("Choose") {
                            showingCategoryPicker = true
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingCategoryPicker = true
                    }

                    if selectedCategory == nil && !categoryName.isEmpty {
                        Text("New category: \(categoryName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Project")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        project.name = name

                        var cat: Category? = selectedCategory

                        // If no category is selected but we have a name, create/find category
                        if cat == nil && !categoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                            let descriptor = FetchDescriptor<Category>(
                                predicate: #Predicate<Category> { category in
                                    category.name == categoryName
                                }
                            )
                            let existingCategories = try? modelContext.fetch(descriptor)
                            if let existing = existingCategories?.first {
                                cat = existing
                            } else {
                                cat = Category(name: categoryName)
                                modelContext.insert(cat!)
                            }
                        }

                        project.category = cat
                        try? modelContext.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .onAppear {
                name = project.name
                categoryName = project.category?.name ?? ""
                selectedCategory = project.category
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerView(
                    categories: existingCategories,
                    selectedCategory: $selectedCategory,
                    customCategoryName: $categoryName
                )
            }
        }
    }
}

struct LogPastSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let project: Project

    @State private var startDate = Date()
    @State private var duration: TimeInterval = 3600 // Default to 1 hour
    @State private var customDurationText = "1:00"
    @State private var showingDatePicker = false

    private let durationPresets: [(String, TimeInterval)] = [
        ("15 min", 15 * 60),
        ("30 min", 30 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("4 hours", 4 * 60 * 60),
        ("8 hours", 8 * 60 * 60)
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Session Details") {
                    HStack {
                        Text("Project")
                        Spacer()
                        Text(project.name)
                            .foregroundColor(.secondary)
                    }
                }

                Section("When") {
                    HStack {
                        Text("Start Date & Time")
                        Spacer()
                        Button(action: { showingDatePicker = true }) {
                            Text(startDate.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.blue)
                        }
                    }
                }

                Section("Duration") {
                    // Preset duration buttons
                    VStack(spacing: 8) {
                        HStack {
                            ForEach(Array(durationPresets.prefix(3).enumerated()), id: \.element.0) { index, preset in
                                Button(action: {
                                    duration = preset.1
                                    customDurationText = formatDuration(preset.1)
                                }) {
                                    Text(preset.0)
                                        .font(.caption)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .frame(maxWidth: .infinity)
                                        .background(duration == preset.1 ? Color.blue : Color.gray.opacity(0.2))
                                        .foregroundColor(duration == preset.1 ? .white : .primary)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack {
                            ForEach(Array(durationPresets.suffix(3).enumerated()), id: \.element.0) { index, preset in
                                Button(action: {
                                    duration = preset.1
                                    customDurationText = formatDuration(preset.1)
                                }) {
                                    Text(preset.0)
                                        .font(.caption)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .frame(maxWidth: .infinity)
                                        .background(duration == preset.1 ? Color.blue : Color.gray.opacity(0.2))
                                        .foregroundColor(duration == preset.1 ? .white : .primary)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Custom duration input
                    HStack {
                        Text("Custom Duration")
                        Spacer()
                        TextField("1:30", text: $customDurationText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .keyboardType(.asciiCapable)
                            .onChange(of: customDurationText) { oldValue, newValue in
                                if let parsedDuration = parseDurationString(newValue) {
                                    duration = parsedDuration
                                }
                            }
                    }

                    Text("Format: hours:minutes (e.g., 1:30 for 1 hour 30 minutes)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Summary") {
                    HStack {
                        Text("Start Time")
                        Spacer()
                        Text(startDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("End Time")
                        Spacer()
                        Text(endDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(DurationFormatter.string(from: duration))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Log Past Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePastSession()
                    }
                    .disabled(duration <= 0)
                }
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationView {
                DatePicker("Start Date & Time", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(WheelDatePickerStyle())
                    .navigationTitle("Select Start Time")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingDatePicker = false
                            }
                        }
                    }
            }
        }
    }

    private var endDate: Date {
        startDate.addingTimeInterval(duration)
    }

    private func savePastSession() {
        let session = WorkSession(
            start: startDate,
            end: endDate
        )
        session.project = project
        session.lastResume = nil // Past sessions are complete, not active
        session.elapsedBeforePause = 0 // Not used for completed sessions

        modelContext.insert(session)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving past session: \(error)")
        }
    }

    private func formatDuration(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        return "\(hours):\(String(format: "%02d", minutes))"
    }

    private func parseDurationString(_ string: String) -> TimeInterval? {
        let components = string.split(separator: ":")
        guard components.count == 2,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              hours >= 0,
              minutes >= 0,
              minutes < 60 else {
            return nil
        }
        return TimeInterval(hours * 3600 + minutes * 60)
    }
}

struct StartInPastView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let project: Project

    @State private var startDate = Date().addingTimeInterval(-3600) // Default to 1 hour ago
    @State private var showingDatePicker = false

    private let pastTimePresets: [(String, TimeInterval)] = [
        ("15 min ago", -15 * 60),
        ("30 min ago", -30 * 60),
        ("1 hour ago", -60 * 60),
        ("2 hours ago", -2 * 60 * 60),
        ("4 hours ago", -4 * 60 * 60),
        ("Start of day", 0) // Special case - will be calculated
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Session Details") {
                    HStack {
                        Text("Project")
                        Spacer()
                        Text(project.name)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Start Time") {
                    HStack {
                        Text("Started at")
                        Spacer()
                        Button(action: { showingDatePicker = true }) {
                            Text(startDate.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.blue)
                        }
                    }

                    // Preset past time buttons
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                        ForEach(pastTimePresets, id: \.0) { preset in
                            Button(action: {
                                if preset.0 == "Start of day" {
                                    // Set to start of current day (midnight)
                                    let calendar = Calendar.current
                                    startDate = calendar.startOfDay(for: Date())
                                } else {
                                    startDate = Date().addingTimeInterval(preset.1)
                                }
                            }) {
                                Text(preset.0)
                                    .font(.caption)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This will start a new timer from the selected past time.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        let elapsed = Date().timeIntervalSince(startDate)
                        if elapsed > 0 {
                            Text("Time since start: \(formatDuration(elapsed))")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else {
                            Text("Start time must be in the past")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Start From Past")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Start Timer") {
                        startPastSession()
                    }
                    .disabled(startDate >= Date())
                }
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationView {
                DatePicker("Start Date & Time", selection: $startDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(WheelDatePickerStyle())
                    .navigationTitle("Select Start Time")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingDatePicker = false
                            }
                        }
                    }
            }
        }
    }

    private func startPastSession() {
        // Create a new session that started in the past but is currently active
        let session = WorkSession(start: startDate, end: nil)
        session.project = project

        // Calculate how much time has already elapsed since the past start time
        let elapsedSincePastStart = Date().timeIntervalSince(startDate)

        // Set up the session to reflect that it's been running since the past time
        session.elapsedBeforePause = elapsedSincePastStart
        session.lastResume = Date() // Mark as currently active from now

        modelContext.insert(session)

        do {
            try modelContext.save()
            // Schedule hourly chimes for this active session
            scheduleHourlyNotifications(for: session)
            dismiss()
        } catch {
            print("Error saving past start session: \(error)")
        }
    }

    // Schedule hourly chime notifications at the top of each hour while a session is running
    private func scheduleHourlyNotifications(for session: WorkSession) {
        let center = UNUserNotificationCenter.current()

        // Schedule notifications for the next 24 hours at the top of each hour
        let calendar = Calendar.current
        let now = Date()

        for hour in 0..<24 {
            guard let nextHour = calendar.date(byAdding: .hour, value: hour, to: now) else { continue }

            // Get the start of this hour (e.g., 2:35 PM becomes 3:00 PM for next hour)
            let startOfHour = calendar.dateInterval(of: .hour, for: nextHour)?.start ?? nextHour

            // Only schedule if this hour boundary is in the future
            guard startOfHour > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Hourly Time Reminder"
            content.body = "🕐 Working on \(project.name) - \(calendar.component(.hour, from: startOfHour)):00"
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.hour, .minute], from: startOfHour),
                repeats: false
            )

            let identifier = "\(session.id.uuidString)-hour-\(hour)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            center.add(request) { error in
                if let error = error {
                    print("Schedule hourly notification error: \(error)")
                }
            }
        }
    }

    private func formatDuration(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        return "\(hours):\(String(format: "%02d", minutes))"
    }
}
