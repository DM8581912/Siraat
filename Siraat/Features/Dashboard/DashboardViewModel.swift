import Combine
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var settings: ReaderSettings = .default
    @Published private(set) var readingPosition: QuranReadingPosition?
    @Published private(set) var prayerSchedule: DailyPrayerSchedule?
    @Published private(set) var qiblaDirection: QiblaDirection?
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
        }
    }

    func requestLocation() {
        locationManager?.requestLocation()
    }

    func schedulePrayerReminders() {
        Task {
            guard let prayerSchedule, let prayerNotificationService else {
                errorMessage = "Prayer times are needed before reminders can be scheduled."
                return
            }

            do {
                try await prayerNotificationService.scheduleReminders(for: prayerSchedule, settings: reminderSettings)
                reminderStatusText = reminderSettings.isEnabled ? "Today’s prayer reminders are scheduled" : "Prayer reminders are off"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateUtilities(for coordinate: LocationCoordinate) {
        locationStatusText = String(format: "%.3f, %.3f", coordinate.latitude, coordinate.longitude)
        prayerSchedule = prayerTimesService?.schedule(for: Date(), coordinate: coordinate, calendar: .current)
        qiblaDirection = qiblaService?.direction(from: coordinate, headingDegrees: locationManager?.headingDegrees)
    }
}
