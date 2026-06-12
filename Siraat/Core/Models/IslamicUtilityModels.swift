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
