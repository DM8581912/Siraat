import Foundation

protocol PrayerTimesServicing {
    func schedule(
        for date: Date,
        coordinate: LocationCoordinate,
        calendar: Calendar,
        method: CalculationMethod,
        madhab: Madhab,
        highLatitudeRule: HighLatitudeRule?,
        adjustments: PrayerAdjustments
    ) -> DailyPrayerSchedule
}

/// Prayer-time computation backed by the vendored Adhan library (batoulapps/adhan-swift),
/// a widely-used, reference-correct implementation of the standard calculation methods.
/// This replaces the previous hand-rolled astronomical math, which was never validated
/// against an authoritative source. See `PrayerTimesValidationTests` for the proof that
/// these outputs match Aladhan reference timetables.
struct PrayerTimesService: PrayerTimesServicing {
    func schedule(
        for date: Date = Date(),
        coordinate: LocationCoordinate,
        calendar: Calendar = .current,
        method: CalculationMethod = .muslimWorldLeague,
        madhab: Madhab = .shafi,
        highLatitudeRule: HighLatitudeRule? = nil,
        adjustments: PrayerAdjustments = PrayerAdjustments()
    ) -> DailyPrayerSchedule {
        let coordinates = Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // Civil calendar day at the location/device timezone. Adhan computes UTC instants
        // for this day; display formats them back into the local timezone.
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)

        var params = method.params
        params.madhab = madhab
        // nil = pick the rule Adhan recommends for this latitude (sane automatic default).
        params.highLatitudeRule = highLatitudeRule ?? HighLatitudeRule.recommended(for: coordinates)
        params.adjustments = adjustments

        guard
            let prayerTimes = PrayerTimes(
                coordinates: coordinates,
                date: dateComponents,
                calculationParameters: params
            )
        else {
            // Solar math undefined (e.g. extreme polar day). Return an empty day rather
            // than crash; the UI degrades to "times unavailable".
            return DailyPrayerSchedule(date: date, coordinate: coordinate, times: [])
        }

        return DailyPrayerSchedule(
            date: date,
            coordinate: coordinate,
            times: [
                PrayerTime(name: .fajr, date: prayerTimes.fajr),
                PrayerTime(name: .sunrise, date: prayerTimes.sunrise),
                PrayerTime(name: .dhuhr, date: prayerTimes.dhuhr),
                PrayerTime(name: .asr, date: prayerTimes.asr),
                PrayerTime(name: .maghrib, date: prayerTimes.maghrib),
                PrayerTime(name: .isha, date: prayerTimes.isha)
            ]
        )
    }
}
