import XCTest
@testable import Siraat

/// Proof that the prayer-time engine produces correct times. Each case is validated
/// against the Aladhan reference timetable (api.aladhan.com) for 2026-06-15 using the
/// matching calculation method and the Standard (Shafi'i) Asr madhab.
///
/// Cities are deliberately low/mid-latitude so no high-latitude twilight rule applies,
/// making the comparison apples-to-apples. Houston is in CDT on this date, so a passing
/// Houston case also proves Daylight Saving Time is handled correctly (the previous
/// hand-rolled implementation was prone to a one-hour DST error).
///
/// Tolerance is 6 minutes — tight enough to catch the real defects (wrong method ≈ 15–30
/// min off, wrong madhab Asr ≈ 60 min off, DST ≈ 60 min off) while allowing for minor
/// rounding/algorithm differences between Adhan and Aladhan. Observed deltas are ≤ ~3 min.
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

    /// High-latitude cities where the Adhan library's recommended high-latitude rule
    /// (seventhOfTheNight for lat > 48°) is exercised. Validated against Aladhan with
    /// latitudeAdjustmentMethod=ONE_SEVENTH on 2026-03-15 (near equinox — avoids polar
    /// day/night extremes while still requiring the rule). Tolerance widened to 8 min
    /// because the two implementations apply the one-seventh cap at slightly different
    /// rounding/truncation points.
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

    func testHighLatitudePrayerTimesMatchAladhanReference() {
        let service = PrayerTimesService()
        let tolerance = 8

        for ref in highLatitudeReferences {
            let timeZone = TimeZone(identifier: ref.timeZone)!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            // Near-equinox date: high-latitude rule applies but no polar day/night.
            let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!

            let schedule = service.schedule(
                for: date,
                coordinate: LocationCoordinate(latitude: ref.latitude, longitude: ref.longitude),
                calendar: calendar,
                method: ref.method,
                madhab: .shafi,
                highLatitudeRule: nil  // let Adhan pick seventhOfTheNight automatically
            )

            XCTAssertFalse(schedule.times.isEmpty, "\(ref.city): schedule returned no times")

            func minutesOfDay(_ name: PrayerName) -> Int {
                guard let prayer = schedule.times.first(where: { $0.name == name }) else { return -1 }
                let comps = calendar.dateComponents([.hour, .minute], from: prayer.date)
                return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }

            let expected: [(PrayerName, Int)] = [
                (.fajr, ref.fajr), (.sunrise, ref.sunrise), (.dhuhr, ref.dhuhr),
                (.asr, ref.asr), (.maghrib, ref.maghrib), (.isha, ref.isha)
            ]

            for (name, want) in expected {
                let got = minutesOfDay(name)
                let delta = abs(got - want)
                XCTAssertLessThanOrEqual(
                    delta, tolerance,
                    "\(ref.city) \(name.rawValue): computed \(got / 60):\(String(format: "%02d", got % 60)) vs reference \(want / 60):\(String(format: "%02d", want % 60)) — Δ\(delta) min"
                )
            }
        }
    }

    func testPrayerTimesMatchAladhanReference() {
        let service = PrayerTimesService()
        let tolerance = 6

        for ref in references {
            let timeZone = TimeZone(identifier: ref.timeZone)!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!

            let schedule = service.schedule(
                for: date,
                coordinate: LocationCoordinate(latitude: ref.latitude, longitude: ref.longitude),
                calendar: calendar,
                method: ref.method,
                madhab: .shafi,
                highLatitudeRule: nil
            )

            func minutesOfDay(_ name: PrayerName) -> Int {
                guard let prayer = schedule.times.first(where: { $0.name == name }) else { return -1 }
                let comps = calendar.dateComponents([.hour, .minute], from: prayer.date)
                return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }

            let expected: [(PrayerName, Int)] = [
                (.fajr, ref.fajr), (.sunrise, ref.sunrise), (.dhuhr, ref.dhuhr),
                (.asr, ref.asr), (.maghrib, ref.maghrib), (.isha, ref.isha)
            ]

            for (name, want) in expected {
                let got = minutesOfDay(name)
                let delta = abs(got - want)
                XCTAssertLessThanOrEqual(
                    delta, tolerance,
                    "\(ref.city) \(name.rawValue): computed \(got / 60):\(String(format: "%02d", got % 60)) vs reference \(want / 60):\(String(format: "%02d", want % 60)) — Δ\(delta) min"
                )
            }
        }
    }

    /// Prove that per-prayer manual adjustments shift times by the expected amount.
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

        func minutes(from schedule: DailyPrayerSchedule, prayer: PrayerName) -> Int {
            guard let p = schedule.times.first(where: { $0.name == prayer }) else { return -1 }
            let comps = calendar.dateComponents([.hour, .minute], from: p.date)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }

        XCTAssertEqual(minutes(from: adjusted, prayer: .fajr) - minutes(from: baseline, prayer: .fajr), 3,
                       "Fajr should shift +3 min")
        XCTAssertEqual(minutes(from: adjusted, prayer: .dhuhr) - minutes(from: baseline, prayer: .dhuhr), -2,
                       "Dhuhr should shift -2 min")
        XCTAssertEqual(minutes(from: adjusted, prayer: .asr) - minutes(from: baseline, prayer: .asr), 5,
                       "Asr should shift +5 min")
        XCTAssertEqual(minutes(from: adjusted, prayer: .maghrib), minutes(from: baseline, prayer: .maghrib),
                       "Maghrib should be unchanged")
    }
}
