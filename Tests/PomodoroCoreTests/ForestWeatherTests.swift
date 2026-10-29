import XCTest
@testable import PomodoroCore

final class ForestWeatherTests: XCTestCase {
    func testWeatherCycleIsDeterministicAndUsesEveryWeather() {
        let samples = (0..<4).map { ForestAtmosphere.sample(at: Double($0) * 90 + 20, seed: 17) }
        XCTAssertEqual(Set(samples.map(\.weather)), Set(ForestWeather.allCases))
        for (index, sample) in samples.enumerated() {
            XCTAssertEqual(sample, ForestAtmosphere.sample(at: Double(index) * 90 + 380, seed: 17))
            XCTAssertEqual(sample.transitionProgress, 1)
        }
    }

    func testWeatherBoundariesFadeContinuouslyRatherThanFlashing() {
        for boundary in [90.0, 180, 270, 360] {
            let before = ForestAtmosphere.sample(at: boundary - 0.000_001, seed: .max)
            let after = ForestAtmosphere.sample(at: boundary + 0.000_001, seed: .max)
            XCTAssertEqual(before.sunStrength, after.sunStrength, accuracy: 0.000_001)
            XCTAssertEqual(before.cloudCover, after.cloudCover, accuracy: 0.000_001)
            XCTAssertEqual(before.rainIntensity, after.rainIntensity, accuracy: 0.000_001)
            XCTAssertEqual(before.windStrength, after.windStrength, accuracy: 0.000_001)
        }
    }

    func testInvalidAndExtremeClocksKeepEveryStrengthFiniteAndInRange() {
        let initial = ForestAtmosphere.sample(at: 0, seed: 4)
        for time in [-1.0, -.infinity, .infinity, .nan] {
            XCTAssertEqual(ForestAtmosphere.sample(at: time, seed: 4), initial)
        }
        for time in [Double.greatestFiniteMagnitude, 1e15, 0, 12, 30, 95] {
            let sample = ForestAtmosphere.sample(at: time, seed: .max)
            for strength in [sample.transitionProgress, sample.sunStrength, sample.cloudCover,
                             sample.rainIntensity, sample.windStrength] {
                XCTAssertTrue(strength.isFinite)
                XCTAssertTrue((0...1).contains(strength))
            }
        }
    }

    func testExplicitWeatherCanBeFrozenAndCrossFadedWithoutChangingProgress() {
        let sunny = ForestAtmosphere(weather: .sunny)
        let rain = ForestAtmosphere(weather: .rainy)
        XCTAssertEqual(ForestAtmosphere.blending(from: sunny, to: rain, progress: 0).sunStrength, sunny.sunStrength)
        XCTAssertEqual(ForestAtmosphere.blending(from: sunny, to: rain, progress: 1).rainIntensity, rain.rainIntensity)
        let midpoint = ForestAtmosphere.blending(from: sunny, to: rain, progress: 0.5)
        XCTAssertGreaterThan(midpoint.rainIntensity, 0)
        XCTAssertLessThan(midpoint.rainIntensity, rain.rainIntensity)
        XCTAssertEqual(ForestAtmosphere(weather: .rainy), rain)
    }
}
