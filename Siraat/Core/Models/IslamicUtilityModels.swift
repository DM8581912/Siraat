import CoreLocation
import Foundation

enum PrayerName: String, CaseIterable, Identifiable, Codable, Hashable {
    case fajr
    case sunrise
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fajr: "Fajr"
        case .sunrise: "Sunrise"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }
}

struct PrayerTime: Identifiable, Codable, Equatable {
    var id: PrayerName { name }
    let name: PrayerName
    let date: Date
}

struct DailyPrayerSchedule: Codable, Equatable {
    let date: Date
    let coordinate: LocationCoordinate
    let times: [PrayerTime]

    var nextPrayer: PrayerTime? {
        let now = Date()
        return times.first { $0.date > now } ?? times.first
    }
}

struct LocationCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct QiblaDirection: Equatable {
    let bearingDegrees: Double
    let headingDegrees: Double?

    var compassOffsetDegrees: Double? {
        guard let headingDegrees else { return nil }
        return QiblaMath.normalizedDegrees(bearingDegrees - headingDegrees)
    }

    var displayBearing: String {
        "\(Int(bearingDegrees.rounded()))°"
    }
}

struct PrayerReminderSettings: Codable, Equatable {
    var isEnabled: Bool
    var minutesBefore: Int

    static let `default` = PrayerReminderSettings(isEnabled: false, minutesBefore: 10)
}

// Prayer-time calculation is delegated to the vendored, battle-tested Adhan library
// (github.com/batoulapps/adhan-swift) rather than hand-rolled astronomical math.
// `CalculationMethod`, `Madhab`, and `HighLatitudeRule` below are Adhan's own types;
// we only add display/UI conveniences and a region-based default here.

extension CalculationMethod: Identifiable {
    public var id: String { rawValue }

    /// Methods we offer in the UI (Adhan's `.other` is an internal sentinel, hidden).
    static var selectable: [CalculationMethod] {
        [.muslimWorldLeague, .northAmerica, .egyptian, .ummAlQura, .karachi,
         .dubai, .qatar, .kuwait, .singapore, .turkey, .tehran, .moonsightingCommittee]
    }

    var displayName: String {
        switch self {
        case .muslimWorldLeague: "Muslim World League"
        case .northAmerica: "ISNA (North America)"
        case .egyptian: "Egyptian General Authority"
        case .ummAlQura: "Umm al-Qura (Makkah)"
        case .karachi: "University of Karachi"
        case .dubai: "Dubai (UAE)"
        case .qatar: "Qatar"
        case .kuwait: "Kuwait"
        case .singapore: "Singapore / SE Asia"
        case .turkey: "Diyanet (Turkey)"
        case .tehran: "Tehran (Iran)"
        case .moonsightingCommittee: "Moonsighting Committee"
        case .other: "Custom"
        }
    }

    /// Best-guess default seeded from the device region the first time only; the user
    /// can override in Settings. Falls back to MWL globally. Never overrides a saved choice.
    static func regionalDefault(regionCode: String? = Locale.current.region?.identifier) -> CalculationMethod {
        switch regionCode?.uppercased() {
        case "US", "CA", "MX": return .northAmerica
        case "SA", "BH", "OM", "YE": return .ummAlQura
        case "AE": return .dubai
        case "KW": return .kuwait
        case "QA": return .qatar
        case "EG", "LY", "SD", "DZ", "MA", "TN", "JO", "SY", "IQ", "LB", "PS": return .egyptian
        case "PK", "IN", "BD", "AF", "LK": return .karachi
        case "SG", "MY", "ID", "BN", "PH": return .singapore
        case "TR": return .turkey
        case "IR": return .tehran
        case "GB", "IE": return .moonsightingCommittee
        default: return .muslimWorldLeague
        }
    }
}

extension Madhab: Identifiable {
    public var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .shafi: "Standard (Shafi'i, Maliki, Hanbali)"
        case .hanafi: "Hanafi"
        }
    }
}

extension HighLatitudeRule: Identifiable {
    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .middleOfTheNight: "Middle of the night"
        case .seventhOfTheNight: "One-seventh of the night"
        case .twilightAngle: "Twilight angle"
        }
    }
}
