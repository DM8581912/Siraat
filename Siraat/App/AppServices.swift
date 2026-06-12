import Foundation

@MainActor
final class AppServices: ObservableObject {
    let audioStreamManager: AudioStreamManager
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
        audioStreamManager: AudioStreamManager = AudioStreamManager(),
        secretsProvider: SecretsProviding = SecretsProvider(),
        translationService: TranslationServicing? = nil,
        quranDatabaseManager: QuranDatabaseManaging = QuranDatabaseManager(),
        recitationCorrectionService: RecitationCorrectionServicing = RecitationCorrectionService(),
        recitationAnalysisProvider: RecitationAnalysisProviding = HybridRecitationAnalysisProvider(),
        quranAudioPlayer: QuranAudioPlayer = QuranAudioPlayer(),
        locationManager: LocationManager = LocationManager(),
        prayerTimesService: PrayerTimesServicing = PrayerTimesService(),
        prayerNotificationService: PrayerNotificationServicing = PrayerNotificationService(),
        qiblaService: QiblaServicing = QiblaService(),
        appearanceController: AppearanceController = AppearanceController()
    ) {
        self.audioStreamManager = audioStreamManager
        self.translationService = translationService ?? TranslationServiceFactory.makeDefault(secretsProvider: secretsProvider)
        self.quranDatabaseManager = quranDatabaseManager
        self.recitationCorrectionService = recitationCorrectionService
        self.recitationAnalysisProvider = recitationAnalysisProvider
        self.quranAudioPlayer = quranAudioPlayer
        self.locationManager = locationManager
        self.prayerTimesService = prayerTimesService
        self.prayerNotificationService = prayerNotificationService
        self.qiblaService = qiblaService
        self.secretsProvider = secretsProvider
        self.appearanceController = appearanceController
    }
}
