import Foundation
import UserNotifications

protocol PrayerNotificationServicing {
    func reminderSettings() -> PrayerReminderSettings
    func saveReminderSettings(_ settings: PrayerReminderSettings)
    func requestAuthorization() async -> Bool
    func scheduleReminders(for schedule: DailyPrayerSchedule, settings: PrayerReminderSettings) async throws
    func cancelPrayerReminders()
}

enum PrayerNotificationError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Notification permission is needed for prayer reminders."
        }
    }
}

final class PrayerNotificationService: PrayerNotificationServicing {
    private let center: UNUserNotificationCenter
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func reminderSettings() -> PrayerReminderSettings {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.prayerReminderSettings.rawValue),
              let settings = try? decoder.decode(PrayerReminderSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    func saveReminderSettings(_ settings: PrayerReminderSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: StorageKey.prayerReminderSettings.rawValue)
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func scheduleReminders(for schedule: DailyPrayerSchedule, settings: PrayerReminderSettings) async throws {
        guard settings.isEnabled else {
            cancelPrayerReminders()
            return
        }

        guard await requestAuthorization() else {
            throw PrayerNotificationError.notAuthorized
        }

        cancelPrayerReminders()

        for prayer in schedule.times where prayer.name != .sunrise {
            let reminderDate = prayer.date.addingTimeInterval(TimeInterval(-settings.minutesBefore * 60))
            guard reminderDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(prayer.name.displayName) soon"
            content.body = settings.minutesBefore == 0 ? "It is time for \(prayer.name.displayName)." : "\(prayer.name.displayName) begins in \(settings.minutesBefore) minutes."
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: notificationIdentifier(for: prayer), content: content, trigger: trigger)
            try await center.add(request)
        }
    }

    func cancelPrayerReminders() {
        center.removePendingNotificationRequests(withIdentifiers: PrayerName.allCases.map { "prayer-reminder-\($0.rawValue)" })
    }

    private func notificationIdentifier(for prayer: PrayerTime) -> String {
        "prayer-reminder-\(prayer.name.rawValue)"
    }
}

private enum StorageKey: String {
    case prayerReminderSettings
}
