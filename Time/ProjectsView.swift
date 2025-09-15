import SwiftUI
import SwiftData

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

    var body: some View {
        // Use TimelineView at the top level to ensure all duration calculations that depend
        // on the current time are recomputed periodically.
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let now = context.date

            // Precompute values outside of the ViewBuilder's returned views.
            let total = project.sessions.reduce(0.0) { acc, s in
                acc + ((s.end ?? now).timeIntervalSince(s.start))
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
                    Text(project.name).font(.largeTitle)
                    Spacer()
                    Text(DurationFormatter.string(from: total))
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

                List {
                    ForEach(project.sessions.sorted(by: { $0.start > $1.start })) { session in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(session.start, style: .date)
                                Text(session.start, style: .time)
                            }
                            Spacer()
                            Text(DurationFormatter.string(from: (session.end ?? now).timeIntervalSince(session.start)))
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
        }
        .onChange(of: scenePhase) { old, new in
            if new == .active {
                // app became active — refresh running session
                runningSession = project.sessions.first(where: { $0.end == nil })
            }
        }
    }

    private func startOrPause() {
        if let running = runningSession {
            // Soft pause: stop the active segment but keep session open.
            if let lr = running.lastResume {
                running.elapsedBeforePause += Date().timeIntervalSince(lr)
                running.lastResume = nil
            }
            // keep runningSession non-nil to allow Stop to finish the session
            // but mark UI state as paused by keeping runningSession (we'll
            // differentiate by lastResume == nil)
            do { try modelContext.save() } catch { print("Error saving pause: \(error)") }
            // cancel notifications while paused
            cancelRunningNotifications(for: running)
        } else {
            // Start or resume
            // If there's an existing session that's not ended, resume it.
            if let other = project.sessions.first(where: { $0.end == nil }) {
                // resume
                other.lastResume = Date()
                runningSession = other
                do { try modelContext.save() } catch { print("Error saving resume: \(error)") }
                scheduleRunningNotification(for: other)
                return
            }
            // otherwise create a new session
            let s = WorkSession(start: Date())
            s.project = project
            modelContext.insert(s)
            runningSession = s
            do { try modelContext.save() } catch { print("Error saving start: \(error)") }
            scheduleRunningNotification(for: s)
        }
    }

    private func stop() {
        if let running = runningSession {
            // finalize the session: accumulate any active segment and set end
            if let lr = running.lastResume {
                running.elapsedBeforePause += Date().timeIntervalSince(lr)
                running.lastResume = nil
            }
            running.end = Date()
            runningSession = nil
            do { try modelContext.save() } catch { print("Error saving stop: \(error)") }
            cancelRunningNotifications(for: running)
        }
    }



    // Schedule a repeating local notification while a session is running to keep the user aware.
    private func scheduleRunningNotification(for session: WorkSession) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Time running"
        content.body = "You're working on \(project.name)."
        content.sound = .default

        // For production: use a 1-hour repeating interval. For quicker testing use a shorter interval (e.g., 60 seconds).
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)

        let request = UNNotificationRequest(identifier: session.id.uuidString, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error { print("Schedule notification error: \(error)") }
        }
    }

    private func cancelRunningNotifications(for session: WorkSession) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [session.id.uuidString])
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
            // compute total using up-to-date 'now' for any running sessions
            let total = project.sessions.reduce(0.0) { acc, s in
                acc + ((s.end ?? now).timeIntervalSince(s.start))
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
