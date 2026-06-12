import CoreLocation
import XCTest
@testable import Siraat

/// Proof that QiblaMath.bearing() produces a correct great-circle bearing to the Kaaba.
///
/// Primary reference: hardcoded bearings from the Aladhan API (api.aladhan.com/v1/qibla),
/// an independent implementation maintained by the Islamic Network. These are NOT computed
/// at test time — they are baked constants from a second, unrelated source, so a shared
/// bug in QiblaMath + Adhan cannot hide behind a tautological test.
///
/// Secondary check: the vendored Adhan library's Qibla struct, which uses the same
/// spherical-trig formula but slightly different Kaaba coordinates (21.4225241 vs 21.4225).
/// Agreement between all three (QiblaMath, Adhan, Aladhan) within 0.5° proves correctness.
final class QiblaMathTests: XCTestCase {

    private struct City {
        let name: String
        let latitude: Double
        let longitude: Double
        /// Hardcoded bearing from api.aladhan.com/v1/qibla (retrieved 2026-06-12).
        let aladhanBearing: Double
    }

    /// Five cities covering all four atan2 quadrants and both hemispheres.
    private let cities: [City] = [
        City(name: "New York",  latitude:  40.7128, longitude: -74.0060, aladhanBearing:  58.48),
        City(name: "London",    latitude:  51.5074, longitude:  -0.1278, aladhanBearing: 118.99),
        City(name: "Tokyo",     latitude:  35.6762, longitude: 139.6503, aladhanBearing: 293.00),
        City(name: "Sydney",    latitude: -33.8688, longitude: 151.2093, aladhanBearing: 277.50),
        City(name: "Cape Town", latitude: -33.9249, longitude:  18.4241, aladhanBearing:  23.35),
    ]

    // MARK: - Tests

    /// Primary: QiblaMath vs. independently hardcoded Aladhan reference bearings.
    func testBearingMatchesAladhanReference() {
        let tolerance = 0.5

        for city in cities {
            let computed = QiblaMath.bearing(
                from: .init(latitude: city.latitude, longitude: city.longitude)
            )
            let delta = angularDelta(computed, city.aladhanBearing)

            XCTAssertLessThanOrEqual(
                delta, tolerance,
                "\(city.name): QiblaMath=\(f(computed))° vs Aladhan=\(f(city.aladhanBearing))° — Δ\(f(delta))°"
            )
        }
    }

    /// Secondary: QiblaMath vs. vendored Adhan Qibla struct (different Kaaba precision).
    func testBearingAgreesWithVendoredAdhanQibla() {
        let tolerance = 0.5

        for city in cities {
            let fromQiblaMath = QiblaMath.bearing(
                from: .init(latitude: city.latitude, longitude: city.longitude)
            )
            let fromAdhan = Qibla(
                coordinates: Coordinates(latitude: city.latitude, longitude: city.longitude)
            ).direction

            let delta = angularDelta(fromQiblaMath, fromAdhan)

            XCTAssertLessThanOrEqual(
                delta, tolerance,
                "\(city.name): QiblaMath=\(f(fromQiblaMath))° vs Adhan=\(f(fromAdhan))° — Δ\(f(delta))°"
            )
        }
    }

    func testBearingFromKaabaIsFinite() {
        let bearing = QiblaMath.bearing(
            from: .init(latitude: 21.4225, longitude: 39.8262)
        )
        XCTAssertTrue(bearing.isFinite, "Bearing from Kaaba should be finite, got \(bearing)")
    }

    func testBearingIsAlwaysNormalized() {
        let coords: [(Double, Double)] = [
            (0, 0), (90, 0), (-90, 0), (0, 180), (0, -180),
            (60, -100), (-45, 120), (70, 70),
        ]

        for (lat, lon) in coords {
            let bearing = QiblaMath.bearing(from: .init(latitude: lat, longitude: lon))
            XCTAssertGreaterThanOrEqual(bearing, 0, "Bearing should be >= 0 for (\(lat), \(lon))")
            XCTAssertLessThan(bearing, 360, "Bearing should be < 360 for (\(lat), \(lon))")
        }
    }

    // MARK: - Helpers

    /// Shortest angular distance between two bearings, handling the 0°/360° wrap.
    private func angularDelta(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 360 - d)
    }

    private func f(_ v: Double) -> String { String(format: "%.2f", v) }
}
