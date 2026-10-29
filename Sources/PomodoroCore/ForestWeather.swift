import Foundation

/// A tiny forest's imaginary weather, independent of location or a forecast.
public enum ForestWeather: String, CaseIterable, Codable, Identifiable, Sendable {
    case sunny, breezy, cloudy, rainy

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .sunny: return "晴光"
        case .breezy: return "微风"
        case .cloudy: return "多云"
        case .rainy: return "细雨"
        }
    }
    public var symbol: String {
        switch self {
        case .sunny: return "sun.max"
        case .breezy: return "wind"
        case .cloudy: return "cloud"
        case .rainy: return "cloud.drizzle"
        }
    }
}

/// Smooth visual strengths rather than abrupt scene changes. Callers supply a
/// common clock (normally timeIntervalSinceReferenceDate), so a badge and scene
/// agree even if a panel was opened later than another one.
public struct ForestAtmosphere: Equatable, Sendable {
    public let weather: ForestWeather
    public let previousWeather: ForestWeather
    public let transitionProgress: Double
    public let sunStrength: Double
    public let cloudCover: Double
    public let rainIntensity: Double
    public let windStrength: Double

    public static let weatherDuration: TimeInterval = 90
    public static let transitionDuration: TimeInterval = 12

    public init(weather: ForestWeather) {
        self.weather = weather
        previousWeather = weather
        transitionProgress = 1
        switch weather {
        case .sunny:
            sunStrength = 0.90; cloudCover = 0.13; rainIntensity = 0; windStrength = 0.16
        case .breezy:
            sunStrength = 0.65; cloudCover = 0.22; rainIntensity = 0; windStrength = 0.72
        case .cloudy:
            sunStrength = 0.18; cloudCover = 0.72; rainIntensity = 0; windStrength = 0.28
        case .rainy:
            sunStrength = 0.06; cloudCover = 0.85; rainIntensity = 0.56; windStrength = 0.42
        }
    }

    public static func sample(at elapsed: TimeInterval, seed: UInt64) -> ForestAtmosphere {
        let time = elapsed.isFinite ? max(0, elapsed) : 0
        let states = ForestWeather.allCases
        // Reduce floating-point time before converting to Int. This remains safe
        // for malformed or extremely large timestamps and all UInt64 seeds.
        let phase = time.truncatingRemainder(dividingBy: weatherDuration * Double(states.count))
        let slot = Int(phase / weatherDuration)
        let current = (slot + Int(seed % UInt64(states.count))) % states.count
        let previous = (current + states.count - 1) % states.count
        let fraction = min(1, phase.truncatingRemainder(dividingBy: weatherDuration) / transitionDuration)
        let eased = fraction * fraction * (3 - 2 * fraction)
        return blending(from: ForestAtmosphere(weather: states[previous]),
                        to: ForestAtmosphere(weather: states[current]), progress: eased)
    }

    public static func blending(from: ForestAtmosphere, to: ForestAtmosphere,
                                progress: Double) -> ForestAtmosphere {
        let p = progress.isFinite ? min(1, max(0, progress)) : 0
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * p }
        return ForestAtmosphere(weather: to.weather, previousWeather: from.weather,
            transitionProgress: p, sunStrength: mix(from.sunStrength, to.sunStrength),
            cloudCover: mix(from.cloudCover, to.cloudCover),
            rainIntensity: mix(from.rainIntensity, to.rainIntensity),
            windStrength: mix(from.windStrength, to.windStrength))
    }

    private init(weather: ForestWeather, previousWeather: ForestWeather, transitionProgress: Double,
                 sunStrength: Double, cloudCover: Double, rainIntensity: Double, windStrength: Double) {
        self.weather = weather
        self.previousWeather = previousWeather
        self.transitionProgress = transitionProgress
        self.sunStrength = sunStrength
        self.cloudCover = cloudCover
        self.rainIntensity = rainIntensity
        self.windStrength = windStrength
    }
}
