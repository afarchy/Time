import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ProjectsView()
                .tabItem {
                    Image(systemName: "clock")
                    Text("Projects")
                }

            WeeklySummaryView()
                .tabItem {
                    Image(systemName: "calendar.badge.clock")
                    Text("Weekly")
                }

            CategorySummaryView()
                .tabItem {
                    Image(systemName: "chart.pie")
                    Text("Categories")
                }
        }
    }
}

#Preview {
    MainTabView()
}