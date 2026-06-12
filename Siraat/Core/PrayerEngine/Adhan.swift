//
//  Adhan.swift
//
//  VENDORED / COMBINED single-file build of the Adhan prayer-times library.
//  Source: Adhan — github.com/batoulapps/adhan-swift (branch: main), MIT License.
//
//  This file is a mechanical concatenation of every .swift file under the
//  upstream `Sources/` directory, with per-file copyright headers and the
//  duplicated `import Foundation` lines removed (a single `import Foundation`
//  is hoisted to the top). No types, declarations, or logic were renamed or
//  altered. Section banners below mark the original upstream file boundaries.
//
//  ----------------------------------------------------------------------------
//  Upstream LICENSE (MIT):
//
//  The MIT License (MIT)
//
//  Copyright (c) 2016 Batoul Apps
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//  ----------------------------------------------------------------------------
//

import Foundation


// MARK: - Sources/Units/Angle.swift

struct Angle: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    var degrees: Double
    
    init(_ value: Double) {
        self.degrees = value
    }
    
    init(radians: Double) {
        self.degrees = (radians * 180.0) / .pi
    }
    
    init(floatLiteral value: Double) {
        self.degrees = value
    }
    
    init(integerLiteral value: Int) {
        self.degrees = Double(value)
    }
    
    var radians: Double {
        return (degrees * .pi) / 180.0
    }
    
    func unwound() -> Angle {
        return Angle(degrees.normalizedToScale(360))
    }
    
    func quadrantShifted() -> Angle {
        if degrees >= -180 && degrees <= 180 {
            return self
        }
        
        return Angle(degrees - (360 * (degrees/360).rounded()))
    }
}

func +(left: Angle, right: Angle) -> Angle {
    return Angle(left.degrees + right.degrees)
}

func -(left: Angle, right: Angle) -> Angle {
    return Angle(left.degrees - right.degrees)
}

func *(left: Angle, right: Angle) -> Angle {
    return Angle(left.degrees * right.degrees)
}

func /(left: Angle, right: Angle) -> Angle {
    return Angle(left.degrees / right.degrees)
}


// MARK: - Sources/Units/Minute.swift

public typealias Minute = Int

internal extension Minute {
    var timeInterval: TimeInterval {
        return TimeInterval(self * 60)
    }
}


// MARK: - Sources/Extensions/MathUtilities.swift

internal extension Double {

    func normalizedToScale(_ max: Double) -> Double {
        return self - (max * (floor(self / max)))
    }
}


// MARK: - Sources/Extensions/DateUtilities.swift

internal extension Date {

    func roundedMinute(rounding: Rounding = .nearest) -> Date {
        let cal: Calendar = .gregorianUTC
        var components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: self)

        let minute: Double = Double(components.minute ?? 0)
        let second: Double = Double(components.second ?? 0)

        switch rounding {
        case .nearest:
            components.minute = Int(minute + round(second/60))
            components.second = 0
        case .up:
            components.minute = Int(minute + ceil(second/60))
            components.second = 0
        case .none:
            components.minute = Int(minute)
            components.second = Int(second)
        }

        return cal.date(from: components) ?? self
    }
}

internal extension DateComponents {
    
    func settingHour(_ value: Double) -> DateComponents? {
        guard value.isNormal else {
            return nil
        }
        
        let calculatedHours = floor(value)
        let calculatedMinutes = floor((value - calculatedHours) * 60)
        let calculatedSeconds = floor((value - (calculatedHours + calculatedMinutes/60)) * 60 * 60)
        
        var components = self
        components.hour = Int(calculatedHours)
        components.minute = Int(calculatedMinutes)
        components.second = Int(calculatedSeconds)
        
        return components
    }
}

internal extension Calendar {
    
    /// All calculations are done using a gregorian calendar with the UTC timezone
    static let gregorianUTC: Calendar = {
        guard let utc = TimeZone(identifier: "UTC") else {
            fatalError("Unable to instantiate UTC TimeZone.")
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal
    }()
}


// MARK: - Sources/Models/Rouding.swift

public enum Rounding: String, Codable, CaseIterable {
    case nearest
    case up
    case none
}


// MARK: - Sources/Models/Shafaq.swift

/**
 Shafaq is the twilight in the sky. Different madhabs define the appearance of
 twilight differently. These values are used by the MoonsightingComittee method
 for the different ways to calculate Isha.

  *Values*

  **general**

  General is a combination of Ahmer and Abyad.

  **ahmer**

  Ahmer means the twilight is the red glow in the sky. Used by the Shafi, Maliki, and Hanbali madhabs.

  **abyad**

  Abyad means the twilight is the white glow in the sky. Used by the Hanafi madhab.
 */
public enum Shafaq: String, Codable, CaseIterable {
    case general
    case ahmer
    case abyad
}


// MARK: - Sources/Models/Prayer.swift

public enum Prayer: CaseIterable {
    case fajr
    case sunrise
    case dhuhr
    case asr
    case maghrib
    case isha
}


// MARK: - Sources/Models/Madhab.swift

/* Madhab for determining how Asr is calculated */
public enum Madhab: Int, Codable, CaseIterable {
    
    // Also for Maliki, Hanbali, and Jafari
    case shafi = 1
    
    case hanafi = 2

    var shadowLength: Double {
        return Double(self.rawValue)
    }
}


// MARK: - Sources/Models/HighLatitudeRule.swift

/**
  Rule for approximating Fajr and Isha at high latitudes

  *Values*

  **middleOfTheNight**

  Fajr won't be earlier than the midpoint of the night and isha won't be later than the midpoint of the night. This is the default
  value to prevent fajr and isha crossing boundaries.

  **seventhOfTheNight**

  Fajr will never be earlier than the beginning of the last seventh of the night and Isha will never be later than the end of the first seventh of the night.
  This is recommended to use for locations above 48° latitude to prevent prayer times that would be difficult to perform.

  **twilightAngle**

  The night is divided into portions of roughly 1/3. The exact value is derived by dividing the fajr/isha angles by 60.
  This can be used to prevent difficult fajr and isha times at certain locations.
 */
public enum HighLatitudeRule: String, Codable, CaseIterable {
    case middleOfTheNight
    case seventhOfTheNight
    case twilightAngle

    /// Returns the recommended High Latitude Rule for the specified location.
    public static func recommended(for coordinates: Coordinates) -> HighLatitudeRule {
        if coordinates.latitude > 48 {
            return .seventhOfTheNight
        } else {
            return .middleOfTheNight
        }
    }
}


// MARK: - Sources/Models/Coordinates.swift

public struct Coordinates: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
    
    var latitudeAngle: Angle {
        return Angle(latitude)
    }
    
    var longitudeAngle: Angle {
        return Angle(longitude)
    }
}


// MARK: - Sources/Models/PrayerAdjustment.swift

/* Adjustment value for prayer times, in minutes */
public struct PrayerAdjustments: Codable, Equatable {
    public var fajr: Minute
    public var sunrise: Minute
    public var dhuhr: Minute
    public var asr: Minute
    public var maghrib: Minute
    public var isha: Minute

    public init(fajr: Minute = 0, sunrise: Minute = 0, dhuhr: Minute = 0, asr: Minute = 0, maghrib: Minute = 0, isha: Minute = 0) {
        self.fajr = fajr
        self.sunrise = sunrise
        self.dhuhr = dhuhr
        self.asr = asr
        self.maghrib = maghrib
        self.isha = isha
    }
}


// MARK: - Sources/Models/CalculationParameters.swift

/**
  Customizable parameters for calculating prayer times
 */
public struct CalculationParameters: Codable, Equatable {
    public var method: CalculationMethod = .other
    public var fajrAngle: Double
    public var maghribAngle: Double?
    public var ishaAngle: Double
    public var ishaInterval: Minute = 0
    public var madhab: Madhab = .shafi
    public var highLatitudeRule: HighLatitudeRule? = nil
    public var adjustments: PrayerAdjustments = PrayerAdjustments()
    public var rounding: Rounding = .nearest
    public var shafaq: Shafaq = .general
    var methodAdjustments: PrayerAdjustments = PrayerAdjustments()

    init(fajrAngle: Double, ishaAngle: Double) {
        self.fajrAngle = fajrAngle
        self.ishaAngle = ishaAngle
    }

    init(fajrAngle: Double, ishaInterval: Minute) {
        self.init(fajrAngle: fajrAngle, ishaAngle: 0)
        self.ishaInterval = ishaInterval
    }

    init(fajrAngle: Double, ishaAngle: Double, method: CalculationMethod) {
        self.init(fajrAngle: fajrAngle, ishaAngle: ishaAngle)
        self.method = method
    }

    init(fajrAngle: Double, ishaInterval: Minute, method: CalculationMethod) {
        self.init(fajrAngle: fajrAngle, ishaInterval: ishaInterval)
        self.method = method
    }
    
    init(fajrAngle: Double, maghribAngle: Double, ishaAngle: Double, method: CalculationMethod) {
        self.init(fajrAngle: fajrAngle, ishaAngle: ishaAngle, method: method)
        self.maghribAngle = maghribAngle
    }

    func nightPortions(using coordinates: Coordinates) -> (fajr: Double, isha: Double) {
        let currentHighLatitudeRule = highLatitudeRule ?? .recommended(for: coordinates)

        switch currentHighLatitudeRule {
        case .middleOfTheNight:
            return (1/2, 1/2)
        case .seventhOfTheNight:
            return (1/7, 1/7)
        case .twilightAngle:
            return (self.fajrAngle / 60, self.ishaAngle / 60)
        }
    }
}


// MARK: - Sources/Models/CalculationMethod.swift

/**
  Preset calculation parameters for different regions.

  *Descriptions of the different options*

  **muslimWorldLeague**

  Muslim World League. Standard Fajr time with an angle of 18°. Earlier Isha time with an angle of 17°.

  **egyptian**

  Egyptian General Authority of Survey. Early Fajr time using an angle 19.5° and a slightly earlier Isha time using an angle of 17.5°.

  **karachi**

  University of Islamic Sciences, Karachi. A generally applicable method that uses standard Fajr and Isha angles of 18°.

  **ummAlQura**

  Umm al-Qura University, Makkah. Uses a fixed interval of 90 minutes from maghrib to calculate Isha. And a slightly earlier Fajr time
  with an angle of 18.5°. Note: you should add a +30 minute custom adjustment for Isha during Ramadan.

  **dubai**

  Used in the UAE. Slightly earlier Fajr time and slightly later Isha time with angles of 18.2° for Fajr and Isha in addition to 3 minute
  offsets for sunrise, Dhuhr, Asr, and Maghrib.

  **moonsightingCommittee**

  Method developed by Khalid Shaukat, founder of Moonsighting Committee Worldwide. Uses standard 18° angles for Fajr and Isha in addition
  to seasonal adjustment values. This method automatically applies the 1/7 approximation rule for locations above 55° latitude.
  Recommended for North America and the UK.

  **northAmerica**

  Also known as the ISNA method. Can be used for North America, but the moonsightingCommittee method is preferable. Gives later Fajr times and early
  Isha times with angles of 15°.

  **kuwait**

  Standard Fajr time with an angle of 18°. Slightly earlier Isha time with an angle of 17.5°.

  **qatar**

  Same Isha interval as `ummAlQura` but with the standard Fajr time using an angle of 18°.

  **singapore**

  Used in Singapore, Malaysia, and Indonesia. Early Fajr time with an angle of 20° and standard Isha time with an angle of 18°.

  **tehran**

  Institute of Geophysics, University of Tehran. Early Isha time with an angle of 14°. Slightly later Fajr time with an angle of 17.7°.
  Calculates Maghrib based on the sun reaching an angle of 4.5° below the horizon.

  **turkey**

  An approximation of the Diyanet method used in Turkey. This approximation is less accurate outside the region of Turkey.

  **other**

  Defaults to angles of 0°, should generally be used for making a custom method and setting your own values.

*/
public enum CalculationMethod: String, Codable, CaseIterable {

    // Muslim World League
    case muslimWorldLeague

    // Egyptian General Authority of Survey
    case egyptian

    // University of Islamic Sciences, Karachi
    case karachi

    // Umm al-Qura University, Makkah
    case ummAlQura

    // UAE
    case dubai

    // Moonsighting Committee
    case moonsightingCommittee

    // ISNA
    case northAmerica

    // Kuwait
    case kuwait

    // Qatar
    case qatar

    // Singapore
    case singapore

    // Institute of Geophysics, University of Tehran
    case tehran

    // Dianet
    case turkey

    // Other
    case other

    public var params: CalculationParameters {
        switch(self) {
        case .muslimWorldLeague:
            var params = CalculationParameters(fajrAngle: 18, ishaAngle: 17, method: self)
            params.methodAdjustments = PrayerAdjustments(dhuhr: 1)
            return params
        case .egyptian:
            var params = CalculationParameters(fajrAngle: 19.5, ishaAngle: 17.5, method: self)
            params.methodAdjustments = PrayerAdjustments(dhuhr: 1)
            return params
        case .karachi:
            var params = CalculationParameters(fajrAngle: 18, ishaAngle: 18, method: self)
            params.methodAdjustments = PrayerAdjustments(dhuhr: 1)
            return params
        case .ummAlQura:
            return CalculationParameters(fajrAngle: 18.5, ishaInterval: 90, method: self)
        case .dubai:
            var params = CalculationParameters(fajrAngle: 18.2, ishaAngle: 18.2, method: self)
            params.methodAdjustments = PrayerAdjustments(sunrise: -3, dhuhr: 3, asr: 3, maghrib: 3)
            return params
        case .moonsightingCommittee:
            var params = CalculationParameters(fajrAngle: 18, ishaAngle: 18, method: self)
            params.methodAdjustments = PrayerAdjustments(dhuhr: 5, maghrib: 3)
            return params
        case .northAmerica:
            var params = CalculationParameters(fajrAngle: 15, ishaAngle: 15, method: self)
            params.methodAdjustments = PrayerAdjustments(dhuhr: 1)
            return params
        case .kuwait:
            return CalculationParameters(fajrAngle: 18, ishaAngle: 17.5, method: self)
        case .qatar:
            return CalculationParameters(fajrAngle: 18, ishaInterval: 90, method: self)
        case .singapore:
            var params = CalculationParameters(fajrAngle: 20, ishaAngle: 18, method: self)
            params.methodAdjustments = PrayerAdjustments(dhuhr: 1)
            params.rounding = .up
            return params
        case .tehran:
            return CalculationParameters(fajrAngle: 17.7, maghribAngle: 4.5, ishaAngle: 14, method: self)
        case .turkey:
            var params = CalculationParameters(fajrAngle: 18, ishaAngle: 17, method: self)
            params.methodAdjustments = PrayerAdjustments(fajr: 0, sunrise: -7, dhuhr: 5, asr: 4, maghrib: 7, isha: 0)
            return params
        case .other:
            return CalculationParameters(fajrAngle: 0, ishaAngle: 0, method: self)
        }
    }
}


// MARK: - Sources/Astronomy/SolarCoordinates.swift

struct SolarCoordinates {
    
    /* The declination of the sun, the angle between
     the rays of the Sun and the plane of the Earth's equator. */
    let declination: Angle
    
    /* Right ascension of the Sun, the angular distance on the
     celestial equator from the vernal equinox to the hour circle. */
    let rightAscension: Angle
    
    /* Apparent sidereal time, the hour angle of the vernal equinox. */
    let apparentSiderealTime: Angle
    
    init(julianDay: Double) {
        let T = Astronomical.julianCentury(julianDay: julianDay)
        let L0 = Astronomical.meanSolarLongitude(julianCentury: T)
        let Lp = Astronomical.meanLunarLongitude(julianCentury: T)
        let Ω = Astronomical.ascendingLunarNodeLongitude(julianCentury: T)
        let λ = Astronomical.apparentSolarLongitude(julianCentury: T, meanLongitude: L0).radians
        
        let θ0 = Astronomical.meanSiderealTime(julianCentury: T)
        let ΔΨ = Astronomical.nutationInLongitude(solarLongitude: L0, lunarLongitude: Lp, ascendingNode: Ω)
        let Δε = Astronomical.nutationInObliquity(solarLongitude: L0, lunarLongitude: Lp, ascendingNode: Ω)
        
        let ε0 = Astronomical.meanObliquityOfTheEcliptic(julianCentury: T)
        let εapp = Astronomical.apparentObliquityOfTheEcliptic(julianCentury: T, meanObliquityOfTheEcliptic: ε0).radians
        
        /* Equation from Astronomical Algorithms page 165 */
        self.declination = Angle(radians: asin(sin(εapp) * sin(λ)))
        
        /* Equation from Astronomical Algorithms page 165 */
        self.rightAscension = Angle(radians: atan2(cos(εapp) * sin(λ), cos(λ))).unwound()
        
        /* Equation from Astronomical Algorithms page 88 */
        self.apparentSiderealTime = Angle(θ0.degrees + (((ΔΨ * 3600) * cos(Angle(ε0.degrees + Δε).radians)) / 3600))
    }
}


// MARK: - Sources/Astronomy/Astronomical.swift

struct Astronomical {

    /* The geometric mean longitude of the sun. */
    static func meanSolarLongitude(julianCentury T: Double) -> Angle {
        /* Equation from Astronomical Algorithms page 163 */
        let term1 = 280.4664567
        let term2 = 36000.76983 * T
        let term3 = 0.0003032 * pow(T, 2)
        let L0 = term1 + term2 + term3
        return Angle(L0).unwound()
    }

    /* The geometric mean longitude of the moon. */
    static func meanLunarLongitude(julianCentury T: Double) -> Angle {
        /* Equation from Astronomical Algorithms page 144 */
        let term1 = 218.3165
        let term2 = 481267.8813 * T
        let Lp = term1 + term2
        return Angle(Lp).unwound()
    }

    static func ascendingLunarNodeLongitude(julianCentury T: Double) -> Angle {
        /* Equation from Astronomical Algorithms page 144 */
        let term1 = 125.04452
        let term2 = 1934.136261 * T
        let term3 = 0.0020708 * pow(T, 2)
        let term4 = pow(T, 3) / 450000
        let Ω = term1 - term2 + term3 + term4
        return Angle(Ω).unwound()
    }

    /* The mean anomaly of the sun. */
    static func meanSolarAnomaly(julianCentury T: Double) -> Angle {
        /* Equation from Astronomical Algorithms page 163 */
        let term1 = 357.52911
        let term2 = 35999.05029 * T
        let term3 = 0.0001537 * pow(T, 2)
        let M = term1 + term2 - term3
        return Angle(M).unwound()
    }

    /* The Sun's equation of the center. */
    static func solarEquationOfTheCenter(julianCentury T: Double, meanAnomaly M: Angle) -> Angle {
        /* Equation from Astronomical Algorithms page 164 */
        let Mrad = M.radians
        let term1 = (1.914602 - (0.004817 * T) - (0.000014 * pow(T, 2))) * sin(Mrad)
        let term2 = (0.019993 - (0.000101 * T)) * sin(2 * Mrad)
        let term3 = 0.000289 * sin(3 * Mrad)
        return Angle(term1 + term2 + term3)
    }

    /* The apparent longitude of the Sun, referred to the
     true equinox of the date. */
    static func apparentSolarLongitude(julianCentury T: Double, meanLongitude L0: Angle) -> Angle {
        /* Equation from Astronomical Algorithms page 164 */
        let longitude = L0 + Astronomical.solarEquationOfTheCenter(julianCentury: T, meanAnomaly: Astronomical.meanSolarAnomaly(julianCentury: T))
        let Ω = Angle(125.04 - (1934.136 * T))
        let λ = Angle(longitude.degrees - 0.00569 - (0.00478 * sin(Ω.radians)))
        return λ.unwound()
    }

    /* The mean obliquity of the ecliptic, formula
     adopted by the International Astronomical Union. */
    static func meanObliquityOfTheEcliptic(julianCentury T: Double) -> Angle {
        /* Equation from Astronomical Algorithms page 147 */
        let term1 = 23.439291
        let term2 = 0.013004167 * T
        let term3 = 0.0000001639 * pow(T, 2)
        let term4 = 0.0000005036 * pow(T, 3)
        return Angle(term1 - term2 - term3 + term4)
    }

    /* The mean obliquity of the ecliptic, corrected for
     calculating the apparent position of the sun. */
    static func apparentObliquityOfTheEcliptic(julianCentury T: Double, meanObliquityOfTheEcliptic ε0: Angle) -> Angle {
        /* Equation from Astronomical Algorithms page 165 */
        let O: Double = 125.04 - (1934.136 * T)
        return Angle(ε0.degrees + (0.00256 * cos(Angle(O).radians)))
    }

    /* Mean sidereal time, the hour angle of the vernal equinox. */
    static func meanSiderealTime(julianCentury T: Double) -> Angle {
        /* Equation from Astronomical Algorithms page 165 */
        let JD = (T * 36525) + 2451545.0
        let term1 = 280.46061837
        let term2 = 360.98564736629 * (JD - 2451545)
        let term3 = 0.000387933 * pow(T, 2)
        let term4 = pow(T, 3) / 38710000
        let θ = term1 + term2 + term3 - term4
        return Angle(θ).unwound()
    }

    static func nutationInLongitude(solarLongitude L0: Angle, lunarLongitude Lp: Angle, ascendingNode Ω: Angle) -> Double {
        /* Equation from Astronomical Algorithms page 144 */
        let term1 = (-17.2/3600) * sin(Ω.radians)
        let term2 =  (1.32/3600) * sin(2 * L0.radians)
        let term3 =  (0.23/3600) * sin(2 * Lp.radians)
        let term4 =  (0.21/3600) * sin(2 * Ω.radians)
        return term1 - term2 - term3 + term4
    }

    static func nutationInObliquity(solarLongitude L0: Angle, lunarLongitude Lp: Angle, ascendingNode Ω: Angle) -> Double {
        /* Equation from Astronomical Algorithms page 144 */
        let term1 =  (9.2/3600) * cos(Ω.radians)
        let term2 = (0.57/3600) * cos(2 * L0.radians)
        let term3 = (0.10/3600) * cos(2 * Lp.radians)
        let term4 = (0.09/3600) * cos(2 * Ω.radians)
        return term1 + term2 + term3 - term4
    }

    static func altitudeOfCelestialBody(observerLatitude φ: Angle, declination δ: Angle, localHourAngle H: Angle) -> Angle {
        /* Equation from Astronomical Algorithms page 93 */
        let term1 = sin(φ.radians) * sin(δ.radians)
        let term2 = cos(φ.radians) * cos(δ.radians) * cos(H.radians)
        return Angle(radians: asin(term1 + term2))
    }

    static func approximateTransit(longitude L: Angle, siderealTime Θ0: Angle, rightAscension α2: Angle) -> Double {
        /* Equation from page Astronomical Algorithms 102 */
        let Lw = L * -1
        let m0 = ((α2 + Lw - Θ0) / 360).degrees.normalizedToScale(1)
        // For locations near the International Date Line, normalizeWithBound can produce
        // an m0 for the wrong calendar date.  We detect this by comparing m0 to a
        // generalized transit time based on the longitude. If they differ by more than
        // half a day, m0 is off by one cycle and we adjust in the correct direction.
        let expectedTransit = ((12.0 - L.degrees / 15.0) / 24.0).normalizedToScale(1)
        if m0 - expectedTransit > 0.5 {
            return m0 - 1.0
        } else if expectedTransit - m0 > 0.5 {
            return m0 + 1.0
        } else {
            return m0
        }
    }

    /* The time at which the sun is at its highest point in the sky (in universal time) */
    static func correctedTransit(approximateTransit m0: Double, longitude L: Angle, siderealTime Θ0: Angle,
                                 rightAscension α2: Angle, previousRightAscension α1: Angle, nextRightAscension α3: Angle) -> Double {
        /* Equation from page Astronomical Algorithms 102 */
        let Lw = L * -1
        let θ = Angle(Θ0.degrees + (360.985647 * m0)).unwound()
        let α = Astronomical.interpolateAngles(value: α2, previousValue: α1, nextValue: α3, factor: m0).unwound()
        let H = (θ - Lw - α).quadrantShifted()
        let Δm = H / Angle(-360)
        return (m0 + Δm.degrees) * 24
    }

    static func correctedHourAngle(approximateTransit m0: Double, angle h0: Angle, coordinates: Coordinates, afterTransit: Bool, siderealTime Θ0: Angle,
                                   rightAscension α2: Angle, previousRightAscension α1: Angle, nextRightAscension α3: Angle,
                                   declination δ2: Angle, previousDeclination δ1: Angle, nextDeclination δ3: Angle) -> Double {
        /* Equation from page Astronomical Algorithms 102 */
        let Lw = coordinates.longitudeAngle * Angle(-1)
        let term1 = sin(h0.radians) - (sin(coordinates.latitudeAngle.radians) * sin(δ2.radians))
        let term2 = cos(coordinates.latitudeAngle.radians) * cos(δ2.radians)
        let H0 = Angle(radians: acos(term1 / term2))
        let m = afterTransit ? m0 + (H0.degrees / 360) : m0 - (H0.degrees / 360)
        let θ = Angle(Θ0.degrees + (360.985647 * m)).unwound()
        let α = Astronomical.interpolateAngles(value: α2, previousValue: α1, nextValue: α3, factor: m).unwound()
        let δ = Angle(Astronomical.interpolate(value: δ2.degrees, previousValue: δ1.degrees, nextValue: δ3.degrees, factor: m))
        let H = (θ - Lw - α)
        let h = Astronomical.altitudeOfCelestialBody(observerLatitude: coordinates.latitudeAngle, declination: δ, localHourAngle: H)
        let term3 = (h - h0).degrees
        let term4 = 360 * cos(δ.radians) * cos(coordinates.latitudeAngle.radians) * sin(H.radians)
        let Δm = term3 / term4
        return (m + Δm) * 24
    }

    /* Interpolation of a value given equidistant
     previous and next values and a factor
     equal to the fraction of the interpolated
     point's time over the time between values. */
    static func interpolate(value y2: Double, previousValue y1: Double, nextValue y3: Double, factor n: Double) -> Double {
        /* Equation from Astronomical Algorithms page 24 */
        let a = y2 - y1
        let b = y3 - y2
        let c = b - a
        return y2 + ((n/2) * (a + b + (n * c)))
    }

    /* Interpolation of three angles, accounting for
     angle unwinding. */
    static func interpolateAngles(value y2: Angle, previousValue y1: Angle, nextValue y3: Angle, factor n: Double) -> Angle {
        /* Equation from Astronomical Algorithms page 24 */
        let a = (y2 - y1).unwound()
        let b = (y3 - y2).unwound()
        let c = b - a
        return Angle(y2.degrees + ((n/2) * (a.degrees + b.degrees + (n * c.degrees))))
    }

    /* The Julian Day for the given Gregorian date. */
    static func julianDay(year: Int, month: Int, day: Int, hours: Double = 0) -> Double {

        /* Equation from Astronomical Algorithms page 60 */

        // NOTE: Casting to Int is done intentionally for the purpose of decimal truncation

        let Y: Int = month > 2 ? year : year - 1
        let M: Int = month > 2 ? month : month + 12
        let D: Double = Double(day) + (hours / 24)

        let A: Int = Y/100
        let B: Int = 2 - A + (A/4)

        let i0: Int = Int(365.25 * (Double(Y) + 4716))
        let i1: Int = Int(30.6001 * (Double(M) + 1))
        return Double(i0) + Double(i1) + D + Double(B) - 1524.5
    }
    
    /* The Julian Day for the given Gregorian date components. */
    static func julianDay(dateComponents: DateComponents) -> Double {
        let year = dateComponents.year ?? 1
        let month = dateComponents.month ?? 1
        let day = dateComponents.day ?? 1
        let hour: Double = Double(dateComponents.hour ?? 0)
        let minute: Double = Double(dateComponents.minute ?? 0)
        
        return Astronomical.julianDay(year: year, month: month, day: day, hours: hour + (minute / 60))
    }

    /* Julian century from the epoch. */
    static func julianCentury(julianDay JD: Double) -> Double {
        /* Equation from Astronomical Algorithms page 163 */
        return (JD - 2451545.0) / 36525
    }

    /* Checks if the given year is a leap year. */
    static func isLeapYear(_ year: Int) -> Bool {
        if year % 4 != 0 {
            return false
        }

        if year % 100 == 0 && year % 400 != 0 {
            return false
        }

        return true
    }

    /* Twilight adjustment based on observational data for use in the Moonsighting Committee calculation method. */
    static func seasonAdjustedMorningTwilight(latitude: Double, day: Int, year: Int, sunrise: Date) -> Date {
        let a: Double = 75 + ((28.65 / 55.0) * fabs(latitude))
        let b: Double = 75 + ((19.44 / 55.0) * fabs(latitude))
        let c: Double = 75 + ((32.74 / 55.0) * fabs(latitude))
        let d: Double = 75 + ((48.10 / 55.0) * fabs(latitude))

        let adjustment: Double = {
            let dyy = Double(Astronomical.daysSinceSolstice(dayOfYear: day, year: year, latitude: latitude))
            if ( dyy < 91) {
                return a + ( b - a ) / 91.0 * dyy
            } else if ( dyy < 137) {
                return b + ( c - b ) / 46.0 * ( dyy - 91 )
            } else if ( dyy < 183 ) {
                return c + ( d - c ) / 46.0 * ( dyy - 137 )
            } else if ( dyy < 229 ) {
                return d + ( c - d ) / 46.0 * ( dyy - 183 )
            } else if ( dyy < 275 ) {
                return c + ( b - c ) / 46.0 * ( dyy - 229 )
            }

            return b + ( a - b ) / 91.0 * ( dyy - 275 )
        }()

        return sunrise.addingTimeInterval(round(adjustment * -60.0))
    }

    /* Twilight adjustment based on observational data for use in the Moonsighting Committee calculation method. */
    static func seasonAdjustedEveningTwilight(latitude: Double, day: Int, year: Int, sunset: Date, shafaq: Shafaq) -> Date {
        let a, b, c, d: Double
        
        switch shafaq {
        case .general:
            a = 75 + ((25.60 / 55.0) * fabs(latitude))
            b = 75 + ((2.050 / 55.0) * fabs(latitude))
            c = 75 - ((9.210 / 55.0) * fabs(latitude))
            d = 75 + ((6.140 / 55.0) * fabs(latitude))
        case .ahmer:
            a = 62 + ((17.40 / 55.0) * fabs(latitude))
            b = 62 - ((7.160 / 55.0) * fabs(latitude))
            c = 62 + ((5.120 / 55.0) * fabs(latitude))
            d = 62 + ((19.44 / 55.0) * fabs(latitude))
        case .abyad:
            a = 75 + ((25.60 / 55.0) * fabs(latitude))
            b = 75 + ((7.160 / 55.0) * fabs(latitude))
            c = 75 + ((36.84 / 55.0) * fabs(latitude))
            d = 75 + ((81.84 / 55.0) * fabs(latitude))
        }
        
        let adjustment: Double = {
            let dyy = Double(Astronomical.daysSinceSolstice(dayOfYear: day, year: year, latitude: latitude))
            if ( dyy < 91) {
                return a + ( b - a ) / 91.0 * dyy
            } else if ( dyy < 137) {
                return b + ( c - b ) / 46.0 * ( dyy - 91 )
            } else if ( dyy < 183 ) {
                return c + ( d - c ) / 46.0 * ( dyy - 137 )
            } else if ( dyy < 229 ) {
                return d + ( c - d ) / 46.0 * ( dyy - 183 )
            } else if ( dyy < 275 ) {
                return c + ( b - c ) / 46.0 * ( dyy - 229 )
            }

            return b + ( a - b ) / 91.0 * ( dyy - 275 )
        }()

        return sunset.addingTimeInterval(round(adjustment * 60.0))
    }

    /* Solstice calculation to determine a date's seasonal progression. Used in the Moonsighting Committee calculation method. */
    static func daysSinceSolstice(dayOfYear: Int, year: Int, latitude: Double) -> Int {
        var daysSinceSolstice = 0
        let northernOffset = 10
        let southernOffset = Astronomical.isLeapYear(year) ? 173 : 172
        let daysInYear = Astronomical.isLeapYear(year) ? 366 : 365

        if (latitude >= 0) {
            daysSinceSolstice = dayOfYear + northernOffset
            if (daysSinceSolstice >= daysInYear) {
                daysSinceSolstice = daysSinceSolstice - daysInYear
            }
        } else {
            daysSinceSolstice = dayOfYear - southernOffset
            if (daysSinceSolstice < 0) {
                daysSinceSolstice = daysSinceSolstice + daysInYear
            }
        }

        return daysSinceSolstice
    }
}


// MARK: - Sources/Astronomy/SolarTime.swift

struct SolarTime {
    let date: DateComponents
    let observer: Coordinates
    let solar: SolarCoordinates
    let transit: DateComponents
    let sunrise: DateComponents
    let sunset: DateComponents

    private let prevSolar: SolarCoordinates
    private let nextSolar: SolarCoordinates
    private let approxTransit: Double

    init?(date: DateComponents, coordinates: Coordinates) {
        // calculations need to occur at 0h0m UTC
        var date = date
        date.hour = 0
        date.minute = 0

        let julianDay = Astronomical.julianDay(dateComponents: date)
        let prevSolar = SolarCoordinates(julianDay: julianDay - 1)
        let solar = SolarCoordinates(julianDay: julianDay)
        let nextSolar = SolarCoordinates(julianDay: julianDay + 1)

        let m0 = Astronomical.approximateTransit(longitude: coordinates.longitudeAngle, siderealTime: solar.apparentSiderealTime, rightAscension: solar.rightAscension)
        let solarAltitude = Angle(-50.0 / 60.0)

        self.date = date
        self.observer = coordinates
        self.solar = solar
        self.prevSolar = prevSolar
        self.nextSolar = nextSolar
        self.approxTransit = m0


        let transitTime = Astronomical.correctedTransit(approximateTransit: m0, longitude: coordinates.longitudeAngle, siderealTime: solar.apparentSiderealTime,
                                                     rightAscension: solar.rightAscension, previousRightAscension: prevSolar.rightAscension, nextRightAscension: nextSolar.rightAscension)
        let sunriseTime = Astronomical.correctedHourAngle(approximateTransit: m0, angle: solarAltitude, coordinates: coordinates, afterTransit: false, siderealTime: solar.apparentSiderealTime,
                                                       rightAscension: solar.rightAscension, previousRightAscension: prevSolar.rightAscension, nextRightAscension: nextSolar.rightAscension,
                                                       declination: solar.declination, previousDeclination: prevSolar.declination, nextDeclination: nextSolar.declination)
        let sunsetTime = Astronomical.correctedHourAngle(approximateTransit: m0, angle: solarAltitude, coordinates: coordinates, afterTransit: true, siderealTime: solar.apparentSiderealTime,
                                                      rightAscension: solar.rightAscension, previousRightAscension: prevSolar.rightAscension, nextRightAscension: nextSolar.rightAscension,
                                                      declination: solar.declination, previousDeclination: prevSolar.declination, nextDeclination: nextSolar.declination)

        guard let transitDate = date.settingHour(transitTime), let sunriseDate = date.settingHour(sunriseTime), let sunsetDate = date.settingHour(sunsetTime) else {
            return nil
        }

        self.transit = transitDate
        self.sunrise = sunriseDate
        self.sunset = sunsetDate
    }

    func timeForSolarAngle(_ angle: Angle, afterTransit: Bool) -> DateComponents? {
        let hours = Astronomical.correctedHourAngle(approximateTransit: approxTransit, angle: angle, coordinates: observer, afterTransit: afterTransit, siderealTime: solar.apparentSiderealTime,
                                               rightAscension: solar.rightAscension, previousRightAscension: prevSolar.rightAscension, nextRightAscension: nextSolar.rightAscension,
                                               declination: solar.declination, previousDeclination: prevSolar.declination, nextDeclination: nextSolar.declination)
        return date.settingHour(hours)
    }

    // hours from transit
    func afternoon(shadowLength: Double) -> DateComponents? {
        // TODO source shadow angle calculation
        let tangent = Angle(fabs(observer.latitude - solar.declination.degrees))
        let inverse = shadowLength + tan(tangent.radians)
        let angle = Angle(radians: atan(1.0 / inverse))

        return timeForSolarAngle(angle, afterTransit: true)
    }
}


// MARK: - Sources/PrayerTimes.swift

/**
  Prayer times for a location and date using the given calculation parameters.

  All prayer times are in UTC and should be displayed using a DateFormatter that
  has the correct timezone set.
 */
public struct PrayerTimes {
    public let fajr: Date
    public let sunrise: Date
    public let dhuhr: Date
    public let asr: Date
    public let maghrib: Date
    public let isha: Date

    public let coordinates: Coordinates
    public let date: DateComponents
    public let calculationParameters: CalculationParameters

    public init?(coordinates: Coordinates, date: DateComponents, calculationParameters: CalculationParameters) {

        var tempFajr: Date? = nil
        var tempSunrise: Date? = nil
        var tempDhuhr: Date? = nil
        var tempAsr: Date? = nil
        var tempMaghrib: Date? = nil
        var tempIsha: Date? = nil
        let cal: Calendar = .gregorianUTC

        guard let prayerDate = cal.date(from: date),
            let tomorrowDate = cal.date(byAdding: .day, value: 1, to: prayerDate),
            let year = date.year,
            let dayOfYear = cal.ordinality(of: .day, in: .year, for: prayerDate) else {
            return nil
        }

        let tomorrow = cal.dateComponents([.year, .month, .day], from: tomorrowDate)

        self.coordinates = coordinates
        self.date = date
        self.calculationParameters = calculationParameters

        guard let solarTime = SolarTime(date: date, coordinates: coordinates),
            let tomorrowSolarTime = SolarTime(date: tomorrow, coordinates: coordinates),
            let sunriseDate = cal.date(from: solarTime.sunrise),
            let sunsetDate = cal.date(from: solarTime.sunset),
            let tomorrowSunrise = cal.date(from: tomorrowSolarTime.sunrise) else {
                // unable to determine transit, sunrise or sunset aborting calculations
                return nil
        }

        tempSunrise = cal.date(from: solarTime.sunrise)
        tempMaghrib = cal.date(from: solarTime.sunset)
        tempDhuhr = cal.date(from: solarTime.transit)

        if let asrComponents = solarTime.afternoon(shadowLength: calculationParameters.madhab.shadowLength) {
            tempAsr = cal.date(from: asrComponents)
        }

        // get night length
        let night = tomorrowSunrise.timeIntervalSince(sunsetDate)

        if let fajrComponents = solarTime.timeForSolarAngle(Angle(-calculationParameters.fajrAngle), afterTransit: false) {
            tempFajr = cal.date(from: fajrComponents)
        }

        // special case for moonsighting committee above latitude 55
        if calculationParameters.method == .moonsightingCommittee && coordinates.latitude >= 55 {
            let nightFraction = night / 7
            tempFajr = sunriseDate.addingTimeInterval(-nightFraction)
        }

        let safeFajr: Date = {
            guard calculationParameters.method != .moonsightingCommittee else {
                return Astronomical.seasonAdjustedMorningTwilight(latitude: coordinates.latitude, day: dayOfYear, year: year, sunrise: sunriseDate)
            }

            let portion = calculationParameters.nightPortions(using: coordinates).fajr
            let nightFraction = portion * night

            return sunriseDate.addingTimeInterval(-nightFraction)
        }()

        if tempFajr == nil || tempFajr?.compare(safeFajr) == .orderedAscending {
            tempFajr = safeFajr
        }

        // Isha calculation with check against safe value
        if calculationParameters.ishaInterval > 0 {
            tempIsha = tempMaghrib?.addingTimeInterval(calculationParameters.ishaInterval.timeInterval)
        } else {
            if let ishaComponents = solarTime.timeForSolarAngle(Angle(-calculationParameters.ishaAngle), afterTransit: true) {
                tempIsha = cal.date(from: ishaComponents)
            }

            // special case for moonsighting committee above latitude 55
            if calculationParameters.method == .moonsightingCommittee && coordinates.latitude >= 55 {
                let nightFraction = night / 7
                tempIsha = sunsetDate.addingTimeInterval(nightFraction)
            }

            let safeIsha: Date = {
                guard calculationParameters.method != .moonsightingCommittee else {
                    return Astronomical.seasonAdjustedEveningTwilight(latitude: coordinates.latitude, day: dayOfYear, year: year, sunset: sunsetDate, shafaq: calculationParameters.shafaq)
                }

                let portion = calculationParameters.nightPortions(using: coordinates).isha
                let nightFraction = portion * night

                return sunsetDate.addingTimeInterval(nightFraction)
            }()

            if tempIsha == nil || tempIsha?.compare(safeIsha) == .orderedDescending {
                tempIsha = safeIsha
            }
        }
        
        // Maghrib calculation with check against safe value
        if let maghribAngle = calculationParameters.maghribAngle,
            let maghribComponents = solarTime.timeForSolarAngle(Angle(-maghribAngle), afterTransit: true),
            let maghribDate = cal.date(from: maghribComponents),
            // maghrib is considered safe if it falls between sunset and isha
            sunsetDate < maghribDate, (tempIsha?.compare(maghribDate) == .orderedDescending || tempIsha == nil) {
                tempMaghrib = maghribDate
        }

        // if we don't have all prayer times then initialization failed
        guard let fajr = tempFajr,
            let sunrise = tempSunrise,
            let dhuhr = tempDhuhr,
            let asr = tempAsr,
            let maghrib = tempMaghrib,
            let isha = tempIsha else {
                return nil
        }

        // Assign final times to public struct members with all offsets
        self.fajr = fajr.addingTimeInterval(calculationParameters.adjustments.fajr.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.fajr.timeInterval)
            .roundedMinute(rounding: calculationParameters.rounding)
        self.sunrise = sunrise.addingTimeInterval(calculationParameters.adjustments.sunrise.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.sunrise.timeInterval)
            .roundedMinute(rounding: calculationParameters.rounding)
        self.dhuhr = dhuhr.addingTimeInterval(calculationParameters.adjustments.dhuhr.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.dhuhr.timeInterval)
            .roundedMinute(rounding: calculationParameters.rounding)
        self.asr = asr.addingTimeInterval(calculationParameters.adjustments.asr.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.asr.timeInterval)
            .roundedMinute(rounding: calculationParameters.rounding)
        self.maghrib = maghrib.addingTimeInterval(calculationParameters.adjustments.maghrib.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.maghrib.timeInterval)
            .roundedMinute(rounding: calculationParameters.rounding)
        self.isha = isha.addingTimeInterval(calculationParameters.adjustments.isha.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.isha.timeInterval)
            .roundedMinute(rounding: calculationParameters.rounding)
    }

    public func currentPrayer(at time: Date = Date()) -> Prayer? {
        if isha.timeIntervalSince(time) <= 0 {
            return .isha
        } else if maghrib.timeIntervalSince(time) <= 0 {
            return .maghrib
        } else if asr.timeIntervalSince(time) <= 0 {
            return .asr
        } else if dhuhr.timeIntervalSince(time) <= 0 {
            return .dhuhr
        } else if sunrise.timeIntervalSince(time) <= 0 {
            return .sunrise
        } else if fajr.timeIntervalSince(time) <= 0 {
            return .fajr
        }

        return nil
    }

    public func nextPrayer(at time: Date = Date()) -> Prayer? {
        if isha.timeIntervalSince(time) <= 0 {
            return nil
        } else if maghrib.timeIntervalSince(time) <= 0 {
            return .isha
        } else if asr.timeIntervalSince(time) <= 0 {
            return .maghrib
        } else if dhuhr.timeIntervalSince(time) <= 0 {
            return .asr
        } else if sunrise.timeIntervalSince(time) <= 0 {
            return .dhuhr
        } else if fajr.timeIntervalSince(time) <= 0 {
            return .sunrise
        }

        return .fajr
    }

    public func time(for prayer: Prayer) -> Date {
        switch prayer {
        case .fajr:
            return fajr
        case .sunrise:
            return sunrise
        case .dhuhr:
            return dhuhr
        case .asr:
            return asr
        case .maghrib:
            return maghrib
        case .isha:
            return isha
        }
    }
}


// MARK: - Sources/Qibla.swift

public struct Qibla {
    /* The heading to the Qibla from True North */
    public let direction: Double

    public init(coordinates: Coordinates) {
        let makkah = Coordinates(latitude: 21.4225241, longitude: 39.8261818)

        /* Equation from "Spherical Trigonometry For the use of colleges and schools" page 50 */
        let term1 = sin(makkah.longitudeAngle.radians - coordinates.longitudeAngle.radians)
        let term2 = cos(coordinates.latitudeAngle.radians) * tan(makkah.latitudeAngle.radians)
        let term3 = sin(coordinates.latitudeAngle.radians) * cos(makkah.longitudeAngle.radians - coordinates.longitudeAngle.radians)

        direction = Angle(radians: atan2(term1, term2 - term3)).unwound().degrees
    }
}


// MARK: - Sources/SunnahTimes.swift

/* Sunnah times for a location and date using the given prayer times.
 All prayer times are in UTC and should be displayed using a DateFormatter that
 has the correct timezone set. */
public struct SunnahTimes {

    /* The midpoint between Maghrib and Fajr */
    public let middleOfTheNight: Date

    /* The beginning of the last third of the period between Maghrib and Fajr,
     a recommended time to perform Qiyam */
    public let lastThirdOfTheNight: Date

    public init?(from prayerTimes: PrayerTimes) {
        guard let date = Calendar.gregorianUTC.date(from: prayerTimes.date),
            let nextDay = Calendar.gregorianUTC.date(byAdding: .day, value: 1, to: date),
            let nextDayPrayerTimes = PrayerTimes(
                coordinates: prayerTimes.coordinates,
                date: Calendar.gregorianUTC.dateComponents([.year, .month, .day], from: nextDay),
                calculationParameters: prayerTimes.calculationParameters)
            else {
                // unable to determine tomorrow prayer times
                return nil
        }

        let nightDuration = nextDayPrayerTimes.fajr.timeIntervalSince(prayerTimes.maghrib)
        self.middleOfTheNight = prayerTimes.maghrib.addingTimeInterval(nightDuration / 2).roundedMinute()
        self.lastThirdOfTheNight = prayerTimes.maghrib.addingTimeInterval(nightDuration * (2 / 3)).roundedMinute()
    }
}
