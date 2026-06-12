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
}
