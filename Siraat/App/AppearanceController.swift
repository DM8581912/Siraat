import SwiftUI

@MainActor
final class AppearanceController: ObservableObject {
    @Published private(set) var mode: AppearanceMode = .system

    var colorScheme: ColorScheme? {
        switch mode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func update(mode: AppearanceMode) {
        self.mode = mode
    }
}
