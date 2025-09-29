import SwiftUI
import SwiftData
import Charts

struct WeeklySummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workSessions: [WorkSession]
    @State private var selectedWeekStart: Date = Date().startOfWeek()
    @State private var showingWeekPicker = false

    private var weekDays: [Date] {
        (0..<7).map { selectedWeekStart.addingTimeInterval(TimeInterval($0 * 24 * 3600)) }
    }

    private var weeklyData: [DayData] {
        weekDays.map { day in
            let dayStart = Calendar.current.startOfDay(for: day)
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

            let daySessions = workSessions.filter { session in
                session.start >= dayStart && session.start < dayEnd
            }

            var projectTimes: [String: TimeInterval] = [:]
            var totalTime: TimeInterval = 0

            for session in daySessions {
                let duration = session.duration
                totalTime += duration

                let projectName = session.project?.name ?? "No Project"
                projectTimes[projectName, default: 0] += duration
            }

            return DayData(
                date: day,
                projectTimes: projectTimes,
                totalTime: totalTime
            )
        }
    }

    private var weeklyProjectSummary: [ProjectSlice] {
        var projectTotals: [String: (time: TimeInterval, color: String)] = [:]

        for session in sessionsInSelectedWeek {
            let projectName = session.project?.name ?? "No Project"
            let projectColor = session.project?.category?.colorHex ?? "#999999"
            let duration = session.duration

            if let existing = projectTotals[projectName] {
                projectTotals[projectName] = (existing.time + duration, existing.color)
            } else {
                projectTotals[projectName] = (duration, projectColor)
            }
        }

        return projectTotals.compactMap { (name, data) in
            data.time > 0 ? ProjectSlice(
                id: UUID(),
                name: name,
                value: data.time,
                color: data.color
            ) : nil
        }.sorted { $0.value > $1.value }
    }

    private var sessionsInSelectedWeek: [WorkSession] {
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: selectedWeekStart)!
        return workSessions.filter { session in
            session.start >= selectedWeekStart && session.start < weekEnd
        }
    }

    private var weeklyTotalTime: TimeInterval {
        sessionsInSelectedWeek.reduce(0) { $0 + $1.duration }
    }

    private var weekDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Week selector
                Button(action: { showingWeekPicker = true }) {
                    HStack {
                        Text("Week of \(weekDateFormatter.string(from: selectedWeekStart))")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Weekly total
                if weeklyTotalTime > 0 {
                    HStack {
                        Text("Total Time:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(WeeklyDurationFormatter.string(from: weeklyTotalTime))
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom)
                }

                List {
                    // Daily breakdown
                    Section("Daily Breakdown") {
                        ForEach(weeklyData, id: \.date) { dayData in
                            DayRowView(dayData: dayData)
                        }
                    }

                    // Weekly pie chart
                    if !weeklyProjectSummary.isEmpty {
                        Section("Weekly Project Summary") {
                            VStack {
                                Chart(weeklyProjectSummary) { slice in
                                    SectorMark(
                                        angle: .value("Time", slice.value),
                                        innerRadius: .ratio(0.4),
                                        outerRadius: .ratio(0.8)
                                    )
                                    .foregroundStyle(Color(hex: slice.color))
                                    .opacity(0.8)
                                }
                                .chartLegend(.visible)
                                .frame(height: 200)

                                // Project list
                                ForEach(weeklyProjectSummary, id: \.id) { slice in
                                    HStack {
                                        Circle()
                                            .fill(Color(hex: slice.color))
                                            .frame(width: 12, height: 12)
                                        Text(slice.name)
                                            .font(.subheadline)
                                        Spacer()
                                        HStack(spacing: 8) {
                                            Text(WeeklyDurationFormatter.string(from: slice.value))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if weeklyTotalTime > 0 {
                                                Text("(\((slice.value / weeklyTotalTime * 100), specifier: "%.1f")%)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding(.vertical)
                        }
                    } else {
                        Section("Weekly Project Summary") {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.pie")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("No time tracked this week")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Weekly Summary")
            .sheet(isPresented: $showingWeekPicker) {
                WeekPickerView(selectedWeekStart: $selectedWeekStart)
            }
        }
    }
}

struct DayData {
    let date: Date
    let projectTimes: [String: TimeInterval]
    let totalTime: TimeInterval
}

struct DayRowView: View {
    let dayData: DayData

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day header
            HStack {
                Text(dayFormatter.string(from: dayData.date))
                    .font(.headline)
                Text(dateFormatter.string(from: dayData.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if dayData.totalTime > 0 {
                    Text(WeeklyDurationFormatter.string(from: dayData.totalTime))
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Text("No time tracked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Project breakdown
            if !dayData.projectTimes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(dayData.projectTimes.sorted { $0.value > $1.value }), id: \.key) { project, time in
                        HStack {
                            Text("• \(project)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text(WeeklyDurationFormatter.string(from: time))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if dayData.totalTime > 0 {
                                    Text("(\((time / dayData.totalTime * 100), specifier: "%.1f")%)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(.vertical, 4)
    }
}

struct WeekPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedWeekStart: Date
    @State private var currentWeekStart = Date().startOfWeek()

    private var weekOptions: [Date] {
        // Generate last 8 weeks
        (0..<8).map { weeksBack in
            Calendar.current.date(byAdding: .weekOfYear, value: -weeksBack, to: currentWeekStart)!
        }
    }

    private var weekFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(weekOptions, id: \.self) { weekStart in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Week of \(weekFormatter.string(from: weekStart))")
                                .font(.headline)
                            let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!
                            Text("\(weekFormatter.string(from: weekStart)) - \(weekFormatter.string(from: weekEnd))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if weekStart == selectedWeekStart {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedWeekStart = weekStart
                        dismiss()
                    }
                }
            }
            .navigationTitle("Select Week")
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

struct ProjectSlice: Identifiable {
    var id: UUID
    var name: String
    var value: TimeInterval
    var color: String
}

struct WeeklyDurationFormatter {
    static func string(from interval: TimeInterval) -> String {
        let ti = Int(interval)
        let h = ti / 3600
        let m = (ti % 3600) / 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        } else if m > 0 {
            return String(format: "%dm", m)
        } else {
            return "< 1m"
        }
    }
}

extension Date {
    func startOfWeek() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }
}

#Preview {
    WeeklySummaryView()
        .modelContainer(for: [Category.self, Project.self, WorkSession.self])
}