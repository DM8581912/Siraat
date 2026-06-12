import SwiftUI

@main
struct SiraatApp: App {
    @StateObject private var services = AppServices()

    init() {
        SiraatFont.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .tint(SiraatColor.accent)
                .environmentObject(services)
                .environmentObject(services.appearanceController)
        }
    }

    /// In normal launches this is `MainTabView`. The CI screenshot job (see
    /// `.github/workflows/ios-build.yml`) launches the app via simctl with a `UITEST_SCREEN`
    /// env var to render one surface as the root, so each screen can be captured in isolation
    /// for before/after design comparison. The env var is never set in production.
    @ViewBuilder private var rootView: some View {
        if let screen = ProcessInfo.processInfo.environment["UITEST_SCREEN"] {
            UITestRoot(screen: screen)
        } else {
            MainTabView()
        }
    }
}

private struct UITestRoot: View {
    @EnvironmentObject private var services: AppServices
    let screen: String

    var body: some View {
        switch screen {
        case "reader":
            NavigationStack { QuranReaderView() }
        case "recitation":
            NavigationStack { RecitationCorrectionView() }
        case "khutba":
            NavigationStack { LiveTranslationView() }
        default:
            // Dashboard: request location so prayer times populate. CI grants permission and
            // sets a simulated location before launch.
            MainTabView().onAppear { services.locationManager.requestLocation() }
        }
    }
}
