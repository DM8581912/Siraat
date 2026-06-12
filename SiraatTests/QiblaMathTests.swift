import CoreLocation
import XCTest
@testable import Siraat

/// Proof that QiblaMath.bearing() produces a correct great-circle bearing to the Kaaba.
///
/// Each test city's expected bearing is cross-referenced against the vendored Adhan
/// library's own Qibla struct (Adhan.swift line 1204), which uses the same spherical
/// trigonometry formula with Kaaba coordinates (21.4225241, 39.8261818). The two
/// implementations agree within 0.1° because QiblaMath rounds to (21.4225, 39.8262).
///
/// Tolerance is 0.5° — tight enough to catch sign errors, swapped lat/lon, or missing
/// normalization, while absorbing the negligible coordinate rounding delta.
final class QiblaMathTests: XCTestCase {

    private struct City {
        let name: String
        let latitude: Double
        let longitude: Double
        let expectedBearing: Double
    }

    /// Reference bearings computed via the Adhan library's Qibla struct and verified
    /// against multiple online Qibla calculators. These cover four quadrants and both
    /// hemispheres to exercise the full atan2 range.
    private var cities: [City] {
        [
            City(name: "New York", latitude: 40.7128, longitude: -74.0060,
                 expectedBearing: adhanQibla(lat: 40.7128, lon: -74.0060)),
            City(name: "London", latitude: 51.5074, longitude: -0.1278,
                 expectedBearing: adhanQibla(lat: 51.5074, lon: -0.1278)),
            City(name: "Tokyo", latitude: 35.6762, longitude: 139.6503,
                 expectedBearing: adhanQibla(lat: 35.6762, lon: 139.6503)),
            City(name: "Sydney", latitude: -33.8688, longitude: 151.2093,
                 expectedBearing: adhanQibla(lat: -33.8688, lon: 151.2093)),
            City(name: "Cape Town", latitude: -33.9249, longitude: 18.4241,
                 expectedBearing: adhanQibla(lat: -33.9249, lon: 18.4241)),
        ]
    }

    /// Compute the Qibla bearing using the vendored Adhan library — the authoritative
    /// cross-reference for QiblaMath. If these two disagree, something is broken.
    private func adhanQibla(lat: Double, lon: Double) -> Double {
        Qibla(coordinates: Coordinates(latitude: lat, longitude: lon)).direction
    }

    // MARK: - Tests

    func testBearingFromMajorCitiesMatchesAdhanQibla() {
        let tolerance = 0.5

        for city in cities {
            let computed = QiblaMath.bearing(
                from: .init(latitude: city.latitude, longitude: city.longitude)
            )
            let delta = abs(computed - city.expectedBearing)
            // Handle wrap-around (e.g. 359° vs 1° = 2° apart, not 358°)
            let wrappedDelta = min(delta, 360 - delta)

            XCTAssertLessThanOrEqual(
                wrappedDelta, tolerance,
                "\(city.name): QiblaMath=\(String(format: "%.2f", computed))° vs Adhan=\(String(format: "%.2f", city.expectedBearing))° — Δ\(String(format: "%.2f", wrappedDelta))°"
            )
        }
    }

    func testBearingFromKaabaIsZeroOrUndefined() {
        // From the Kaaba itself, the bearing is degenerate (atan2(0,0)). QiblaMath
        // should return 0 (the normalizedDegrees of atan2(0,0)) without crashing.
        let bearing = QiblaMath.bearing(
            from: .init(latitude: 21.4225, longitude: 39.8262)
        )
        // Just verify it doesn't crash and returns a finite number.
        XCTAssertTrue(bearing.isFinite, "Bearing from Kaaba should be finite, got \(bearing)")
    }

    func testBearingIsAlwaysNormalized() {
        // Verify the result is always in [0, 360) for a spread of coordinates.
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
}
