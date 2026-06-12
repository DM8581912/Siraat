import CoreLocation
import Foundation

protocol QiblaServicing {
    func direction(from coordinate: LocationCoordinate, headingDegrees: Double?) -> QiblaDirection
}

struct QiblaService: QiblaServicing {
    func direction(from coordinate: LocationCoordinate, headingDegrees: Double?) -> QiblaDirection {
        QiblaDirection(
            bearingDegrees: QiblaMath.bearing(from: coordinate.clLocationCoordinate),
            headingDegrees: headingDegrees
        )
    }
}
