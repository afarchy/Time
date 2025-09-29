import SwiftUI
import SwiftData
import Charts

struct CategorySummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Category.name)]) private var categories: [Category]
    @State private var categoryToEdit: Category?
    @State private var hasInitializedColors = false

    // Compute total time per category by summing their projects' sessions
    private func totalTime(for category: Category) -> TimeInterval {
        category.projects.reduce(0) { acc, project in
            acc + project.totalTime
        }
    }

    private var series: [CategorySlice] {
        categories.compactMap { category in
            let time = totalTime(for: category)
            // Only include categories that have some time logged
            return time > 0 ? CategorySlice(id: category.id, name: category.name, value: time, color: category.colorHex) : nil
        }
    }

    private func canDeleteCategory(_ category: Category) -> Bool {
        category.projects.isEmpty
    }

    private func deleteCategory(_ category: Category) {
        modelContext.delete(category)
        try? modelContext.save()
    }

    private func ensureCategoriesHaveColors() {
        guard !hasInitializedColors else { return }
        DataMigrationManager.performPostLaunchMigration(context: modelContext)
        hasInitializedColors = true
    }

    var body: some View {
        NavigationView {
            VStack {
                if series.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.pie")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No time tracked yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Start timing your projects to see category breakdowns")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    Chart(series) { slice in
                        SectorMark(
                            angle: .value("Time", slice.value),
                            innerRadius: .ratio(0.4),
                            outerRadius: .ratio(0.8)
                        )
                        .foregroundStyle(Color(hex: slice.color))
                        .opacity(0.8)
                    }
                    .chartLegend(.visible)
                    .frame(height: 280)
                    .padding()

                    List {
                        Section("Time by Category") {
                            ForEach(series.sorted(by: { $0.value > $1.value }), id: \.id) { slice in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: slice.color))
                                        .frame(width: 12, height: 12)
                                    Text(slice.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(DurationFormatter.string(from: slice.value))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        Section("All Categories") {
                            ForEach(categories, id: \.id) { category in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: category.colorHex))
                                        .frame(width: 12, height: 12)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.name)
                                            .font(.headline)
                                        Text("\(category.projects.count) project\(category.projects.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()

                                    Button(action: {
                                        categoryToEdit = category
                                    }) {
                                        Image(systemName: "pencil")
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())

                                    if canDeleteCategory(category) {
                                        Button(action: {
                                            deleteCategory(category)
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .onAppear {
                ensureCategoriesHaveColors()
            }
            .sheet(item: $categoryToEdit) { category in
                CategoryEditView(category: category)
                    .environment(\.modelContext, modelContext)
            }
        }
    }
}

fileprivate struct CategorySlice: Identifiable {
    var id: UUID
    var name: String
    var value: TimeInterval
    var color: String
}

struct CategoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var category: Category
    @State private var editedName: String = ""
    @State private var editedColorHex: String = ""

    private let predefinedColors = [
        "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FECA57",
        "#FF9FF3", "#54A0FF", "#5F27CD", "#00D2D3", "#FF9F43",
        "#74B9FF", "#A29BFE", "#FD79A8", "#FDCB6E", "#6C5CE7",
        "#E17055", "#81ECEC", "#FAB1A0", "#00B894", "#E84393"
    ]

    var body: some View {
        NavigationStack {
            VStack {
                Text("Edit Category: \(category.name)")
                    .font(.title)
                    .padding()

                Form {
                    Section("Category Details") {
                        TextField("Category Name", text: $editedName)
                    }

                    Section("Color") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                            ForEach(predefinedColors, id: \.self) { color in
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(editedColorHex == color ? Color.primary : Color.clear, lineWidth: 3)
                                    )
                                    .onTapGesture {
                                        editedColorHex = color
                                    }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        category.name = editedName
                        category.colorHex = editedColorHex
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            editedName = category.name
            editedColorHex = category.colorHex
        }
    }
}

struct CategorySummaryView_Previews: PreviewProvider {
    static var previews: some View {
        CategorySummaryView()
            .modelContainer(for: [Category.self, Project.self, WorkSession.self])
    }
}
