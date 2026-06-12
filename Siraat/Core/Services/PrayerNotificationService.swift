import Foundation
import UserNotifications

protocol PrayerNotificationServicing {
    func reminderSettings() -> PrayerReminderSettings
    func saveReminderSettings(_ settings: PrayerReminderSettings)
    func requestAuthorization() async -> Bool
    func scheduleReminders(for schedules: [DailyPrayerSchedule], settings: PrayerReminderSettings) async throws
    func cancelPrayerReminders() async
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

    /// Schedules one-shot reminders for the EXACT computed time of each prayer across the
    /// supplied days. The caller passes the next N days of freshly computed schedules and
    /// re-arms on every launch, so the user always has accurate upcoming reminders.
    ///
    /// This replaces the previous `repeats: true` `[.hour, .minute]` trigger, which fired
    /// daily at a frozen clock time and drifted as real prayer times shifted day to day and
    /// season to season — a correctness failure for the app's most important feature.
    func scheduleReminders(for schedules: [DailyPrayerSchedule], settings: PrayerReminderSettings) async throws {
        guard settings.isEnabled else {
            await cancelPrayerReminders()
            return
        }

        guard await requestAuthorization() else {
            throw PrayerNotificationError.notAuthorized
        }

        await cancelPrayerReminders()

        let now = Date()
        let calendar = Calendar.current
        // iOS keeps at most 64 pending notifications per app; cap defensively. Five prayers
        // × ~7 days = ~35, comfortably under the limit.
        let maxPendingReminders = 60
        var scheduled = 0

        outer: for schedule in schedules {
            for prayer in schedule.times where prayer.name != .sunrise {
                guard scheduled < maxPendingReminders else { break outer }

                let reminderDate = prayer.date.addingTimeInterval(TimeInterval(-settings.minutesBefore * 60))
                // One-shot, future only: skip times that have already passed (e.g. earlier today).
                guard reminderDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "\(prayer.name.displayName) soon"
                content.body = settings.minutesBefore == 0 ? "It is time for \(prayer.name.displayName)." : "\(prayer.name.displayName) begins in \(settings.minutesBefore) minutes."
                content.sound = settings.playAdhanSound
                    ? UNNotificationSound(named: UNNotificationSoundName("Adhan.caf"))
                    : .default

                // Full date components + repeats:false => fires once, at the exact computed
                // instant for that calendar day. No drift.
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: notificationIdentifier(for: prayer, on: reminderDate),
                    content: content,
                    trigger: trigger
                )

                // Isolate failures: one bad request must not abort the remaining prayers.
                do {
                    try await center.add(request)
                    scheduled += 1
                } catch {
                    continue
                }
            }
        }
    }

    func cancelPrayerReminders() async {
        // Identifiers are now date-suffixed (one per prayer per day), so we can't enumerate
        // them from a fixed list — query the pending set and remove ours by prefix.
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static let identifierPrefix = "prayer-reminder-"

    private static let identifierDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func notificationIdentifier(for prayer: PrayerTime, on date: Date) -> String {
        "\(Self.identifierPrefix)\(prayer.name.rawValue)-\(Self.identifierDateFormatter.string(from: date))"
    }
}

private enum StorageKey: String {
    case prayerReminderSettings
}
