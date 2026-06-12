import XCTest
@testable import Siraat

final class IslamicUtilityTests: XCTestCase {
    func testQiblaBearingFromNewYorkIsNortheast() {
        let newYork = LocationCoordinate(latitude: 40.7128, longitude: -74.0060)

        let direction = QiblaService().direction(from: newYork, headingDegrees: nil)

        XCTAssertEqual(direction.bearingDegrees, 58, accuracy: 2)
    }

    func testPrayerScheduleContainsOrderedDailyTimes() {
        let service = PrayerTimesService()
        let coordinate = LocationCoordinate(latitude: 40.7128, longitude: -74.0060)
        let date = Date(timeIntervalSince1970: 1_781_136_000)

        let schedule = service.schedule(for: date, coordinate: coordinate, calendar: .current)

        XCTAssertEqual(schedule.times.map(\.name), [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha])
        XCTAssertEqual(schedule.times.map(\.date), schedule.times.map(\.date).sorted())
    }
}
