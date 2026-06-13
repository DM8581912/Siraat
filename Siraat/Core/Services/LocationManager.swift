import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var coordinate: LocationCoordinate?
    @Published private(set) var headingDegrees: Double?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    /// True when the coordinate was set manually (city search / lat-lon entry) rather
    /// than from the device GPS. Heading updates are unavailable in this mode.
    @Published private(set) var isManualLocation = false

    private static let manualCoordinateKey = "manualLocationCoordinate"

    private let manager = CLLocationManager()

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
        restoreManualCoordinate()
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
            startHeadingUpdates()
        case .denied, .restricted:
            if coordinate == nil {
                errorMessage = "Location permission is needed for prayer times and qibla direction."
            }
        @unknown default:
            errorMessage = "Location authorization could not be determined."
        }
    }

    /// Set a manual location override. Persisted across launches. Clears when the user
    /// grants device location permission and a GPS fix arrives.
    func setManualCoordinate(_ coord: LocationCoordinate) {
        coordinate = coord
        isManualLocation = true
        if let data = try? JSONEncoder().encode(coord) {
            UserDefaults.standard.set(data, forKey: Self.manualCoordinateKey)
        }
    }

    /// Remove the manual override so the next GPS fix takes over.
    func clearManualCoordinate() {
        isManualLocation = false
        UserDefaults.standard.removeObject(forKey: Self.manualCoordinateKey)
    }

    private func restoreManualCoordinate() {
        guard let data = UserDefaults.standard.data(forKey: Self.manualCoordinateKey),
              let coord = try? JSONDecoder().decode(LocationCoordinate.self, from: data) else { return }
        coordinate = coord
        isManualLocation = true
    }

    func startHeadingUpdates() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.headingFilter = 2
        manager.headingOrientation = .portrait
        // trueHeading is only computed while location updates are running. Without this
        // the device can only give magneticHeading, which is wrong against a true bearing.
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stopHeadingUpdates() {
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = self.manager.authorizationStatus
            if self.manager.authorizationStatus == .authorizedWhenInUse || self.manager.authorizationStatus == .authorizedAlways {
                self.manager.requestLocation()
                self.startHeadingUpdates()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            if self.isManualLocation { self.clearManualCoordinate() }
            self.coordinate = LocationCoordinate(location.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // trueHeading is negative when it can't be determined (location off / no fix yet).
        // The qibla is a TRUE bearing, so feeding magneticHeading would make the arrow
        // wrong by the local magnetic declination. Publish nil instead — the UI then
        // shows the static bearing-from-north rather than a confidently-wrong arrow.
        let trueHeading: Double? = newHeading.trueHeading >= 0 ? newHeading.trueHeading : nil
        Task { @MainActor in
            self.headingDegrees = trueHeading
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
