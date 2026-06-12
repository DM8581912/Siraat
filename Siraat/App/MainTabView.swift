import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case quran
    case liveTranslation
    case settings
}

struct MainTabView: View {
    @EnvironmentObject private var appearanceController: AppearanceController
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(selectedTab: $selectedTab)
            }
            .tabItem {
                Label("Dashboard", systemImage: "sun.max")
            }
            .tag(AppTab.dashboard)

            NavigationStack {
                QuranReaderView()
            }
            .tabItem {
                Label("Quran", systemImage: "book.closed")
            }
            .tag(AppTab.quran)

            NavigationStack {
                LiveTranslationView()
            }
            .tabItem {
                Label("Translate", systemImage: "waveform.and.mic")
            }
            .tag(AppTab.liveTranslation)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .preferredColorScheme(appearanceController.colorScheme)
    }
}
