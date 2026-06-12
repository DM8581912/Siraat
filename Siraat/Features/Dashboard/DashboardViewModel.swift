import Combine
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var settings: ReaderSettings = .default
    @Published private(set) var readingPosition: QuranReadingPosition?
    @Published private(set) var prayerSchedule: DailyPrayerSchedule?
    @Published private(set) var qiblaDirection: QiblaDirection?
    @Published private(set) var hijriDateText = HijriDate.formatted()
    @Published private(set) var verseOfTheDay: QuranVerse?
    @Published private(set) var locationStatusText = "Location not set"
    @Published private(set) var reminderSettings: PrayerReminderSettings = .default
    @Published private(set) var reminderStatusText = "Prayer reminders are off"
    @Published var errorMessage: String?

    private var databaseManager: QuranDatabaseManaging?
    private var locationManager: LocationManager?
    private var prayerTimesService: PrayerTimesServicing?
    private var prayerNotificationService: PrayerNotificationServicing?
    private var qiblaService: QiblaServicing?
    private var cancellables = Set<AnyCancellable>()
    private var didAutoRescheduleReminders = false

    func configure(
        databaseManager: QuranDatabaseManaging,
        locationManager: LocationManager,
        prayerTimesService: PrayerTimesServicing,
        prayerNotificationService: PrayerNotificationServicing,
        qiblaService: QiblaServicing
    ) {
        guard self.databaseManager == nil else { return }
        self.databaseManager = databaseManager
        self.locationManager = locationManager
        self.prayerTimesService = prayerTimesService
        self.prayerNotificationService = prayerNotificationService
        self.qiblaService = qiblaService

        locationManager.$coordinate
            .compactMap { $0 }
            .sink { [weak self] coordinate in
                self?.updateUtilities(for: coordinate)
            }
            .store(in: &cancellables)

        locationManager.$headingDegrees
            .sink { [weak self] heading in
                guard let self, let coordinate = self.locationManager?.coordinate else { return }
                self.qiblaDirection = self.qiblaService?.direction(from: coordinate, headingDegrees: heading)
            }
            .store(in: &cancellables)

        locationManager.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)
    }

    func load() {
        Task {
            guard let databaseManager else { return }
            bookmarks = await databaseManager.cachedBookmarks()
            settings = await databaseManager.readerSettings()
            readingPosition = await databaseManager.readingPosition()
            reminderSettings = prayerNotificationService?.reminderSettings() ?? .default
            reminderStatusText = reminderSettings.isEnabled ? "Reminders enabled \(reminderSettings.minutesBefore) minutes before each prayer" : "Prayer reminders are off"
            hijriDateText = HijriDate.formatted(dayAdjustment: settings.hijriDayAdjustment)

            // Verse of the day: deterministic per calendar day, spread across the whole
            // Qur'an so consecutive days aren't adjacent ayat.
            let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 1
            // Use unsigned magnitude rather than abs(): the overflow-multiply can land on
            // Int.min, and abs(Int.min) traps. .magnitude is total over every Int.
            let globalNumber = Int((day &* 2_654_435_761).magnitude % 6236) + 1
            verseOfTheDay = await databaseManager.verse(globalNumber: globalNumber)

            // Recompute prayer times with the freshly loaded calculation method/madhab
            // (e.g. after the user changes them in Settings) using the last fix.
            if let coordinate = locationManager?.coordinate {
                updateUtilities(for: coordinate)
            }
        }
    }

    func requestLocation() {
        locationManager?.requestLocation()
    }

    func schedulePrayerReminders() {
        Task {
            guard let prayerNotificationService else { return }
            guard let coordinate = locationManager?.coordinate else {
                errorMessage = "Prayer times are needed before reminders can be scheduled."
                return
            }

            do {
                let schedules = upcomingSchedules(from: coordinate, days: reminderScheduleDays)
                try await prayerNotificationService.scheduleReminders(for: schedules, settings: reminderSettings)
                reminderStatusText = reminderSettings.isEnabled
                    ? "Reminders set for the next \(reminderScheduleDays) days"
                    : "Prayer reminders are off"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateUtilities(for coordinate: LocationCoordinate) {
        locationStatusText = String(format: "%.3f, %.3f", coordinate.latitude, coordinate.longitude)
        prayerSchedule = prayerTimesService?.schedule(
            for: Date(),
            coordinate: coordinate,
            calendar: .current,
            method: settings.calculationMethod,
            madhab: settings.madhab,
            highLatitudeRule: settings.highLatitudeRule
        )
        qiblaDirection = qiblaService?.direction(from: coordinate, headingDegrees: locationManager?.headingDegrees)
        autoRescheduleRemindersIfNeeded(for: coordinate)
    }

    /// Re-arm reminders once per launch as soon as we have a location and reminders are on.
    /// One-shot triggers (see `PrayerNotificationService`) only cover the days we schedule,
    /// so re-arming each launch is what keeps upcoming reminders accurate over time — the
    /// previous design only re-armed when the user manually tapped "Schedule".
    private func autoRescheduleRemindersIfNeeded(for coordinate: LocationCoordinate) {
        guard !didAutoRescheduleReminders, reminderSettings.isEnabled else { return }
        didAutoRescheduleReminders = true
        Task {
            let schedules = upcomingSchedules(from: coordinate, days: reminderScheduleDays)
            try? await prayerNotificationService?.scheduleReminders(for: schedules, settings: reminderSettings)
        }
    }

    private let reminderScheduleDays = 7

    private func upcomingSchedules(from coordinate: LocationCoordinate, days: Int) -> [DailyPrayerSchedule] {
        guard let prayerTimesService else { return [] }
        let calendar = Calendar.current
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { return nil }
            return prayerTimesService.schedule(
                for: day,
                coordinate: coordinate,
                calendar: calendar,
                method: settings.calculationMethod,
                madhab: settings.madhab,
                highLatitudeRule: settings.highLatitudeRule
            )
        }
    }
}
