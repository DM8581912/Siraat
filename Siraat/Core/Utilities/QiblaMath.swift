import CoreLocation
import Foundation

enum QiblaMath {
    static let kaaba = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)

    static func bearing(from coordinate: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D = kaaba) -> Double {
        let lat1 = coordinate.latitude.degreesToRadians
        let lat2 = destination.latitude.degreesToRadians
        let deltaLongitude = (destination.longitude - coordinate.longitude).degreesToRadians

        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        return normalizedDegrees(atan2(y, x).radiansToDegrees)
    }

    static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }
}

extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
}
