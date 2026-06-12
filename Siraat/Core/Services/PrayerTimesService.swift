import Foundation

protocol PrayerTimesServicing {
    func schedule(
        for date: Date,
        coordinate: LocationCoordinate,
        calendar: Calendar,
        method: CalculationMethod,
        madhab: Madhab
    ) -> DailyPrayerSchedule
}

struct PrayerTimesService: PrayerTimesServicing {
    func schedule(
        for date: Date = Date(),
        coordinate: LocationCoordinate,
        calendar: Calendar = .current,
        method: CalculationMethod = .muslimWorldLeague,
        madhab: Madhab = .shafii
    ) -> DailyPrayerSchedule {
        var calendar = calendar
        calendar.timeZone = .current

        let solar = solarComponents(for: date, coordinate: coordinate, calendar: calendar)
        let noon = solar.noonMinutes

        // Sunrise/sunset use a fixed 90.833° zenith (refraction + solar radius) and are
        // valid at all but truly polar latitudes. If they saturate there, fall back to noon.
        let sunHourAngle = hourAngleMinutes(zenith: 90.833, latitude: coordinate.latitude, declination: solar.declination)
        let dayHalf = sunHourAngle ?? 0
        let sunriseMinutes = noon - dayHalf
        let maghribMinutes = noon + dayHalf
        // Night length (Maghrib → next Sunrise), used for high-latitude twilight fallback.
        let nightMinutes = 1440 - 2 * dayHalf

        // Fajr / Isha by twilight angle, with a high-latitude "angle-based" fallback when
        // the sun never reaches the depression angle (acos saturates).
        let fajrMinutes: Double
        if let fajrAngle = hourAngleMinutes(zenith: 90 + method.fajrAngle, latitude: coordinate.latitude, declination: solar.declination) {
            fajrMinutes = noon - fajrAngle
        } else {
            fajrMinutes = sunriseMinutes - (method.fajrAngle / 60) * nightMinutes
        }

        let ishaMinutes: Double
        if let interval = method.ishaIntervalMinutes {
            // Umm al-Qura: fixed interval after Maghrib.
            ishaMinutes = maghribMinutes + interval
        } else if let ishaAngle = hourAngleMinutes(zenith: 90 + method.ishaAngle, latitude: coordinate.latitude, declination: solar.declination) {
            ishaMinutes = noon + ishaAngle
        } else {
            ishaMinutes = maghribMinutes + (method.ishaAngle / 60) * nightMinutes
        }

        let asrMinutes = noon + asrHourAngleMinutes(latitude: coordinate.latitude, declination: solar.declination, shadowFactor: madhab.asrShadowFactor)

        return DailyPrayerSchedule(
            date: date,
            coordinate: coordinate,
            times: [
                PrayerTime(name: .fajr, date: date(fromMinutes: fajrMinutes, on: date, calendar: calendar)),
                PrayerTime(name: .sunrise, date: date(fromMinutes: sunriseMinutes, on: date, calendar: calendar)),
                PrayerTime(name: .dhuhr, date: date(fromMinutes: noon, on: date, calendar: calendar)),
                PrayerTime(name: .asr, date: date(fromMinutes: asrMinutes, on: date, calendar: calendar)),
                PrayerTime(name: .maghrib, date: date(fromMinutes: maghribMinutes, on: date, calendar: calendar)),
                PrayerTime(name: .isha, date: date(fromMinutes: ishaMinutes, on: date, calendar: calendar))
            ]
        )
    }

    private func solarComponents(for date: Date, coordinate: LocationCoordinate, calendar: Calendar) -> (noonMinutes: Double, declination: Double) {
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let gamma = 2 * Double.pi / 365 * (day - 1)
        let equationOfTime = 229.18 * (
            0.000075 +
            0.001868 * cos(gamma) -
            0.032077 * sin(gamma) -
            0.014615 * cos(2 * gamma) -
            0.040849 * sin(2 * gamma)
        )
        let declination = (
            0.006918 -
            0.399912 * cos(gamma) +
            0.070257 * sin(gamma) -
            0.006758 * cos(2 * gamma) +
            0.000907 * sin(2 * gamma) -
            0.002697 * cos(3 * gamma) +
            0.00148 * sin(3 * gamma)
        ).radiansToDegrees
        let timezoneMinutes = Double(TimeZone.current.secondsFromGMT(for: date)) / 60
        let noonMinutes = 720 - 4 * coordinate.longitude - equationOfTime + timezoneMinutes
        return (noonMinutes, declination)
    }

    /// Half-day arc length in minutes for a given zenith. Returns nil when the sun never
    /// reaches that zenith (high-latitude case), so callers can apply a twilight fallback.
    private func hourAngleMinutes(zenith: Double, latitude: Double, declination: Double) -> Double? {
        let cosHourAngle = (
            cos(zenith.degreesToRadians) -
            sin(latitude.degreesToRadians) * sin(declination.degreesToRadians)
        ) / (
            cos(latitude.degreesToRadians) * cos(declination.degreesToRadians)
        )
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }
        return acos(cosHourAngle).radiansToDegrees * 4
    }

    private func asrHourAngleMinutes(latitude: Double, declination: Double, shadowFactor: Double) -> Double {
        let angle = atan(1 / (shadowFactor + tan(abs(latitude - declination).degreesToRadians))).radiansToDegrees
        let cosHourAngle = (
            sin(angle.degreesToRadians) -
            sin(latitude.degreesToRadians) * sin(declination.degreesToRadians)
        ) / (
            cos(latitude.degreesToRadians) * cos(declination.degreesToRadians)
        )
        return acos(clamped(cosHourAngle)).radiansToDegrees * 4
    }

    /// Builds a concrete Date from "minutes after local midnight". Uses calendar component
    /// resolution rather than raw second arithmetic so it stays correct across DST
    /// transitions (adding seconds to midnight is off by an hour on transition days).
    /// Handles minute values outside 0–1440 (e.g. Isha after midnight, or a negative
    /// high-latitude fallback) by rolling the day.
    private func date(fromMinutes minutes: Double, on date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let totalSeconds = Int((minutes * 60).rounded())
        let dayOffset = Int(floor(Double(totalSeconds) / 86_400))
        let secondsInDay = totalSeconds - dayOffset * 86_400
        let hour = secondsInDay / 3_600
        let minute = (secondsInDay % 3_600) / 60
        let second = secondsInDay % 60
        let baseDay = calendar.date(byAdding: .day, value: dayOffset, to: dayStart) ?? dayStart
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: baseDay) ?? baseDay
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }
}
