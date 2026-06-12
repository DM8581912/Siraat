import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: ReaderSettings = .default
    @Published var prayerReminderSettings: PrayerReminderSettings = .default
    @Published var secretsStatus = "External translation providers are optional. When no key is configured, the app uses an on-device mock provider and nothing leaves your phone."

    private var databaseManager: QuranDatabaseManaging?
    private var prayerNotificationService: PrayerNotificationServicing?
    private var appearanceController: AppearanceController?

    func configure(
        databaseManager: QuranDatabaseManaging,
        prayerNotificationService: PrayerNotificationServicing,
        appearanceController: AppearanceController
    ) {
        guard self.databaseManager == nil else { return }
        self.databaseManager = databaseManager
        self.prayerNotificationService = prayerNotificationService
        self.appearanceController = appearanceController
    }

    func load() {
        Task {
            settings = await databaseManager?.readerSettings() ?? .default
            prayerReminderSettings = prayerNotificationService?.reminderSettings() ?? .default
            appearanceController?.update(mode: settings.appearanceMode)
        }
    }

    func save() {
        Task {
            await databaseManager?.saveReaderSettings(settings)
            appearanceController?.update(mode: settings.appearanceMode)
            prayerNotificationService?.saveReminderSettings(prayerReminderSettings)
            if !prayerReminderSettings.isEnabled {
                prayerNotificationService?.cancelPrayerReminders()
            }
        }
    }
}
