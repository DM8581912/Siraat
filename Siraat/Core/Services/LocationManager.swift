import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var coordinate: LocationCoordinate?
    @Published private(set) var headingDegrees: Double?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
            startHeadingUpdates()
        case .denied, .restricted:
            errorMessage = "Location permission is needed for prayer times and qibla direction."
        @unknown default:
            errorMessage = "Location authorization could not be determined."
        }
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
