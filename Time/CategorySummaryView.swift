import SwiftUI
import SwiftData
import Charts

struct CategorySummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Category.name)]) private var categories: [Category]

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
            return time > 0 ? CategorySlice(id: category.id, name: category.name, value: time) : nil
        }
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
                        .foregroundStyle(by: .value("Category", slice.name))
                        .opacity(0.8)
                    }
                    .chartLegend(.visible)
                    .frame(height: 280)
                    .padding()

                    List {
                        Section("Time by Category") {
                            ForEach(series.sorted(by: { $0.value > $1.value }), id: \.id) { slice in
                                HStack {
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
                    }
                }
            }
            .navigationTitle("Categories")
        }
    }
}

fileprivate struct CategorySlice: Identifiable {
    var id: UUID
    var name: String
    var value: TimeInterval
}

struct CategorySummaryView_Previews: PreviewProvider {
    static var previews: some View {
        CategorySummaryView()
            .modelContainer(for: [Category.self, Project.self, WorkSession.self])
    }
}
