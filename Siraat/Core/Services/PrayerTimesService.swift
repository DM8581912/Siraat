import Foundation

protocol PrayerTimesServicing {
    func schedule(for date: Date, coordinate: LocationCoordinate, calendar: Calendar) -> DailyPrayerSchedule
}

struct PrayerTimesService: PrayerTimesServicing {
    var fajrAngle: Double = 18
    var ishaAngle: Double = 17
    var asrShadowFactor: Double = 1

    func schedule(for date: Date = Date(), coordinate: LocationCoordinate, calendar: Calendar = .current) -> DailyPrayerSchedule {
        var calendar = calendar
        calendar.timeZone = .current

        let solar = solarComponents(for: date, coordinate: coordinate, calendar: calendar)
        let fajr = dateByAdding(minutes: solar.noonMinutes - hourAngleMinutes(zenith: 90 + fajrAngle, latitude: coordinate.latitude, declination: solar.declination), to: date, calendar: calendar)
        let sunrise = dateByAdding(minutes: solar.noonMinutes - hourAngleMinutes(zenith: 90.833, latitude: coordinate.latitude, declination: solar.declination), to: date, calendar: calendar)
        let dhuhr = dateByAdding(minutes: solar.noonMinutes, to: date, calendar: calendar)
        let asr = dateByAdding(minutes: solar.noonMinutes + asrHourAngleMinutes(latitude: coordinate.latitude, declination: solar.declination), to: date, calendar: calendar)
        let maghrib = dateByAdding(minutes: solar.noonMinutes + hourAngleMinutes(zenith: 90.833, latitude: coordinate.latitude, declination: solar.declination), to: date, calendar: calendar)
        let isha = dateByAdding(minutes: solar.noonMinutes + hourAngleMinutes(zenith: 90 + ishaAngle, latitude: coordinate.latitude, declination: solar.declination), to: date, calendar: calendar)

        return DailyPrayerSchedule(
            date: date,
            coordinate: coordinate,
            times: [
                PrayerTime(name: .fajr, date: fajr),
                PrayerTime(name: .sunrise, date: sunrise),
                PrayerTime(name: .dhuhr, date: dhuhr),
                PrayerTime(name: .asr, date: asr),
                PrayerTime(name: .maghrib, date: maghrib),
                PrayerTime(name: .isha, date: isha)
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

    private func hourAngleMinutes(zenith: Double, latitude: Double, declination: Double) -> Double {
        let cosHourAngle = (
            cos(zenith.degreesToRadians) -
            sin(latitude.degreesToRadians) * sin(declination.degreesToRadians)
        ) / (
            cos(latitude.degreesToRadians) * cos(declination.degreesToRadians)
        )
        let hourAngle = acos(clamped(cosHourAngle)).radiansToDegrees
        return hourAngle * 4
    }

    private func asrHourAngleMinutes(latitude: Double, declination: Double) -> Double {
        let angle = atan(1 / (asrShadowFactor + tan(abs(latitude - declination).degreesToRadians))).radiansToDegrees
        let cosHourAngle = (
            sin(angle.degreesToRadians) -
            sin(latitude.degreesToRadians) * sin(declination.degreesToRadians)
        ) / (
            cos(latitude.degreesToRadians) * cos(declination.degreesToRadians)
        )
        return acos(clamped(cosHourAngle)).radiansToDegrees * 4
    }

    private func dateByAdding(minutes: Double, to date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return startOfDay.addingTimeInterval(minutes * 60)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }
}
