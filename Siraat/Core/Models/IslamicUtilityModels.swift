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

/// Prayer-time calculation conventions. Different Islamic authorities use different
/// Fajr/Isha twilight depression angles (and Umm al-Qura uses a fixed interval after
/// Maghrib for Isha). Imposing a single one on every user produces times that disagree
/// with their local mosque by 10–30 minutes.
enum CalculationMethod: String, CaseIterable, Identifiable, Codable, Hashable {
    case muslimWorldLeague
    case isna
    case egyptian
    case ummAlQura
    case karachi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .muslimWorldLeague: "Muslim World League"
        case .isna: "ISNA (North America)"
        case .egyptian: "Egyptian General Authority"
        case .ummAlQura: "Umm al-Qura (Makkah)"
        case .karachi: "University of Karachi"
        }
    }

    var fajrAngle: Double {
        switch self {
        case .muslimWorldLeague: 18
        case .isna: 15
        case .egyptian: 19.5
        case .ummAlQura: 18.5
        case .karachi: 18
        }
    }

    /// Twilight angle for Isha. Ignored when `ishaIntervalMinutes` is non-nil.
    var ishaAngle: Double {
        switch self {
        case .muslimWorldLeague: 17
        case .isna: 15
        case .egyptian: 17.5
        case .ummAlQura: 18.5 // unused; Isha is a fixed interval after Maghrib
        case .karachi: 18
        }
    }

    /// Umm al-Qura defines Isha as a fixed number of minutes after Maghrib rather
    /// than by a twilight angle. nil means "use `ishaAngle`".
    var ishaIntervalMinutes: Double? {
        switch self {
        case .ummAlQura: 90
        default: nil
        }
    }
}

/// Asr begins when an object's shadow equals its own length plus its noon shadow,
/// multiplied by this factor. Shafi'i/Maliki/Hanbali use 1; Hanafi uses 2 (later Asr).
/// Hardcoding Shafi'i made Asr up to an hour early for Hanafi users.
enum Madhab: String, CaseIterable, Identifiable, Codable, Hashable {
    case shafii
    case hanafi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shafii: "Shafi'i / Maliki / Hanbali"
        case .hanafi: "Hanafi"
        }
    }

    var asrShadowFactor: Double {
        switch self {
        case .shafii: 1
        case .hanafi: 2
        }
    }
}
