import SwiftUI

@main
struct SiraatApp: App {
    @StateObject private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(services)
                .environmentObject(services.appearanceController)
        }
    }
}
