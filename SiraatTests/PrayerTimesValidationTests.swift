import XCTest
@testable import Siraat

/// Proof that the prayer-time engine produces correct times. Each case is validated
/// against the Aladhan reference timetable (api.aladhan.com) using the matching
/// calculation method and the Standard (Shafi'i) Asr madhab.
///
/// Tolerance is 6 minutes for standard latitudes — tight enough to catch real defects
/// (wrong method ≈ 15-30 min, wrong madhab Asr ≈ 60 min, DST ≈ 60 min) while absorbing
/// minor rounding differences. Widened to 8 min for high-latitude cities where the
/// one-seventh cap implementations diverge slightly.
final class PrayerTimesValidationTests: XCTestCase {

    private struct Reference {
        let city: String
        let latitude: Double
        let longitude: Double
        let timeZone: String
        let method: CalculationMethod
        let fajr: Int, sunrise: Int, dhuhr: Int, asr: Int, maghrib: Int, isha: Int
    }

    private func hm(_ h: Int, _ m: Int) -> Int { h * 60 + m }

    /// Low/mid-latitude cities. Date: 2026-06-15. Houston proves DST handling (CDT).
    private var references: [Reference] {
        [
            Reference(city: "Houston", latitude: 29.7604, longitude: -95.3698,
                      timeZone: "America/Chicago", method: .northAmerica,
                      fajr: hm(5, 3), sunrise: hm(6, 21), dhuhr: hm(13, 22),
                      asr: hm(16, 57), maghrib: hm(20, 24), isha: hm(21, 42)),
            Reference(city: "Cairo", latitude: 30.0444, longitude: 31.2357,
                      timeZone: "Africa/Cairo", method: .egyptian,
                      fajr: hm(4, 8), sunrise: hm(5, 53), dhuhr: hm(12, 56),
                      asr: hm(16, 31), maghrib: hm(19, 58), isha: hm(21, 31)),
            Reference(city: "Mecca", latitude: 21.4225, longitude: 39.8262,
                      timeZone: "Asia/Riyadh", method: .ummAlQura,
                      fajr: hm(4, 10), sunrise: hm(5, 38), dhuhr: hm(12, 21),
                      asr: hm(15, 41), maghrib: hm(19, 4), isha: hm(20, 34))
        ]
    }

    /// High-latitude cities. Date: 2026-03-15 (near equinox — avoids polar day/night
    /// extremes while still exercising the seventhOfTheNight rule). Validated against
    /// Aladhan with latitudeAdjustmentMethod=ONE_SEVENTH.
    private var highLatitudeReferences: [Reference] {
        [
            Reference(city: "Reykjavik", latitude: 64.1466, longitude: -21.9426,
                      timeZone: "Atlantic/Reykjavik", method: .muslimWorldLeague,
                      fajr: hm(6, 1), sunrise: hm(7, 46), dhuhr: hm(13, 37),
                      asr: hm(16, 23), maghrib: hm(19, 29), isha: hm(21, 14)),
            Reference(city: "Tromso", latitude: 69.6493, longitude: 18.9553,
                      timeZone: "Europe/Oslo", method: .muslimWorldLeague,
                      fajr: hm(4, 20), sunrise: hm(6, 7), dhuhr: hm(11, 53),
                      asr: hm(14, 21), maghrib: hm(17, 42), isha: hm(19, 28)),
        ]
    }

    // MARK: - Helpers

    /// Minutes since midnight for a prayer in a given schedule and calendar.
    private func minutesOfDay(
        _ name: PrayerName,
        in schedule: DailyPrayerSchedule,
        calendar: Calendar
    ) -> Int {
        guard let prayer = schedule.times.first(where: { $0.name == name }) else { return -1 }
        let comps = calendar.dateComponents([.hour, .minute], from: prayer.date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func formatTime(_ minutes: Int) -> String {
        "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }

    /// Shared assertion: each prayer in `refs` matches the Aladhan reference within `tolerance`.
    private func assertTimesMatchReference(
        _ refs: [Reference],
        date components: DateComponents,
        tolerance: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let service = PrayerTimesService()

        for ref in refs {
            let timeZone = TimeZone(identifier: ref.timeZone)!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let date = calendar.date(from: components)!

            let schedule = service.schedule(
                for: date,
                coordinate: LocationCoordinate(latitude: ref.latitude, longitude: ref.longitude),
                calendar: calendar,
                method: ref.method,
                madhab: .shafi,
                highLatitudeRule: nil
            )

            XCTAssertFalse(schedule.times.isEmpty, "\(ref.city): schedule returned no times",
                           file: file, line: line)

            let expected: [(PrayerName, Int)] = [
                (.fajr, ref.fajr), (.sunrise, ref.sunrise), (.dhuhr, ref.dhuhr),
                (.asr, ref.asr), (.maghrib, ref.maghrib), (.isha, ref.isha)
            ]

            for (name, want) in expected {
                let got = minutesOfDay(name, in: schedule, calendar: calendar)
                let delta = abs(got - want)
                XCTAssertLessThanOrEqual(
                    delta, tolerance,
                    "\(ref.city) \(name.rawValue): computed \(formatTime(got)) vs reference \(formatTime(want)) — Δ\(delta) min",
                    file: file, line: line
                )
            }
        }
    }

    // MARK: - Tests

    func testPrayerTimesMatchAladhanReference() {
        assertTimesMatchReference(
            references,
            date: DateComponents(year: 2026, month: 6, day: 15, hour: 12),
            tolerance: 6
        )
    }

    func testHighLatitudePrayerTimesMatchAladhanReference() {
        assertTimesMatchReference(
            highLatitudeReferences,
            date: DateComponents(year: 2026, month: 3, day: 15, hour: 12),
            tolerance: 8
        )
    }

    func testPrayerAdjustmentsShiftTimes() {
        let service = PrayerTimesService()
        let ref = references[0] // Houston
        let timeZone = TimeZone(identifier: ref.timeZone)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        let coord = LocationCoordinate(latitude: ref.latitude, longitude: ref.longitude)

        let baseline = service.schedule(
            for: date, coordinate: coord, calendar: calendar,
            method: ref.method, madhab: .shafi, highLatitudeRule: nil
        )

        let adjusted = service.schedule(
            for: date, coordinate: coord, calendar: calendar,
            method: ref.method, madhab: .shafi, highLatitudeRule: nil,
            adjustments: PrayerAdjustments(fajr: 3, dhuhr: -2, asr: 5)
        )

        func delta(_ prayer: PrayerName) -> Int {
            minutesOfDay(prayer, in: adjusted, calendar: calendar)
                - minutesOfDay(prayer, in: baseline, calendar: calendar)
        }

        XCTAssertEqual(delta(.fajr), 3, "Fajr should shift +3 min")
        XCTAssertEqual(delta(.dhuhr), -2, "Dhuhr should shift -2 min")
        XCTAssertEqual(delta(.asr), 5, "Asr should shift +5 min")
        XCTAssertEqual(delta(.maghrib), 0, "Maghrib should be unchanged")
    }
}
