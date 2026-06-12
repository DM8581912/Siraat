import Foundation

@MainActor
final class AppServices: ObservableObject {
    // Note: AudioStreamManager is intentionally NOT shared here. Each audio feature
    // (Live Translation, Recitation Correction) owns its own instance so the two
    // can never fight over a single microphone engine. See the feature view models.
    let translationService: TranslationServicing
    let quranDatabaseManager: QuranDatabaseManaging
    let recitationCorrectionService: RecitationCorrectionServicing
    let recitationAnalysisProvider: RecitationAnalysisProviding
    let quranAudioPlayer: QuranAudioPlayer
    let locationManager: LocationManager
    let prayerTimesService: PrayerTimesServicing
    let prayerNotificationService: PrayerNotificationServicing
    let qiblaService: QiblaServicing
    let secretsProvider: SecretsProviding
    let appearanceController: AppearanceController

    init(
        secretsProvider: SecretsProviding = SecretsProvider(),
        translationService: TranslationServicing? = nil,
        quranDatabaseManager: QuranDatabaseManaging = QuranDatabaseManager(),
        recitationCorrectionService: RecitationCorrectionServicing = RecitationCorrectionService(),
        recitationAnalysisProvider: RecitationAnalysisProviding = HybridRecitationAnalysisProvider(),
        quranAudioPlayer: QuranAudioPlayer? = nil,
        locationManager: LocationManager? = nil,
        prayerTimesService: PrayerTimesServicing = PrayerTimesService(),
        prayerNotificationService: PrayerNotificationServicing = PrayerNotificationService(),
        qiblaService: QiblaServicing = QiblaService(),
        appearanceController: AppearanceController? = nil
    ) {
        self.translationService = translationService ?? TranslationServiceFactory.makeDefault(secretsProvider: secretsProvider)
        self.quranDatabaseManager = quranDatabaseManager
        self.recitationCorrectionService = recitationCorrectionService
        self.recitationAnalysisProvider = recitationAnalysisProvider
        // These are @MainActor types: their init() can't be a default-argument
        // expression (evaluated in a nonisolated context), so construct them here in
        // the main-actor-isolated init body instead.
        self.quranAudioPlayer = quranAudioPlayer ?? QuranAudioPlayer()
        self.locationManager = locationManager ?? LocationManager()
        self.prayerTimesService = prayerTimesService
        self.prayerNotificationService = prayerNotificationService
        self.qiblaService = qiblaService
        self.secretsProvider = secretsProvider
        self.appearanceController = appearanceController ?? AppearanceController()
    }
}
