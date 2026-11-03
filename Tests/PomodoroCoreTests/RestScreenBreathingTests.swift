import XCTest
@testable import PomodoroCore

final class RestScreenBreathingTests: XCTestCase {
    func testApprovedPeriodAndTwelvePercentMaximumDimming() {
        XCTAssertEqual(RestScreenBreathing.period, 10)
        XCTAssertEqual(RestScreenBreathing.maximumDimming, 0.12)
        XCTAssertEqual(1 - RestScreenBreathing.opacity(at: 5), 0.88, accuracy: 1e-12)
    }

    func testTwentySecondRestCompletesTwoWholeCycles() {
        let expected: [(TimeInterval, Double)] = [
            (0, 0), (2.5, 0.06), (5, 0.12), (7.5, 0.06),
            (10, 0), (12.5, 0.06), (15, 0.12), (17.5, 0.06), (20, 0)
        ]
        for (elapsed, opacity) in expected {
            XCTAssertEqual(RestScreenBreathing.opacity(at: elapsed), opacity,
                           accuracy: 1e-12, "Elapsed: \(elapsed)")
        }
    }

    func testEachHalfCycleIsMonotonicWithoutBrightnessSpikes() {
        let dimming = (0...500).map { RestScreenBreathing.opacity(at: Double($0) / 100) }
        let returning = (500...1000).map { RestScreenBreathing.opacity(at: Double($0) / 100) }
        XCTAssertTrue(zip(dimming, dimming.dropFirst()).allSatisfy { $0.0 <= $0.1 })
        XCTAssertTrue(zip(returning, returning.dropFirst()).allSatisfy { $0.0 >= $0.1 })
    }

    func testCycleBoundariesAndDarkestPointHaveNoAbruptVelocity() {
        let epsilon = 0.001
        for turningPoint in [0.0, 5, 10, 15, 20] {
            let value = RestScreenBreathing.opacity(at: turningPoint)
            let next = RestScreenBreathing.opacity(at: turningPoint + epsilon)
            XCTAssertLessThan(abs(next - value) / epsilon, 0.00002)
            if turningPoint > 0 {
                let previous = RestScreenBreathing.opacity(at: turningPoint - epsilon)
                XCTAssertLessThan(abs(value - previous) / epsilon, 0.00002)
            }
        }
        XCTAssertEqual(RestScreenBreathing.opacity(at: 10 - epsilon),
                       RestScreenBreathing.opacity(at: 10 + epsilon), accuracy: 1e-12)
    }

    func testLongerSupportedRestsRepeatTheSameCycle() {
        for cycle in 0...17 {
            for phase in [0.0, 0.5, 2.5, 5, 7.5, 9.5] {
                XCTAssertEqual(RestScreenBreathing.opacity(at: Double(cycle) * 10 + phase),
                               RestScreenBreathing.opacity(at: phase), accuracy: 1e-12)
            }
        }
    }

    func testEveryFrameRemainsWithinTheApprovedBrightnessRange() {
        for hundredths in 0...18_000 {
            let opacity = RestScreenBreathing.opacity(at: Double(hundredths) / 100)
            XCTAssertTrue(opacity.isFinite)
            XCTAssertTrue((0...0.12).contains(opacity))
            XCTAssertGreaterThanOrEqual(1 - opacity, 0.88)
        }
    }

    func testInvalidElapsedValuesDoNotDimTheScreen() {
        for elapsed in [-1.0, -Double.leastNonzeroMagnitude, -.infinity, .infinity, .nan] {
            XCTAssertEqual(RestScreenBreathing.opacity(at: elapsed), 0)
        }
    }

    func testExtremeFiniteElapsedValuesStaySafeAndBounded() {
        for elapsed in [Double.greatestFiniteMagnitude, 1e15, 1e100] {
            let opacity = RestScreenBreathing.opacity(at: elapsed)
            XCTAssertTrue(opacity.isFinite)
            XCTAssertTrue((0...0.12).contains(opacity))
        }
    }

    func testReduceMotionKeepsTheInitialBrightnessAtEveryPhase() {
        for elapsed in [0.0, 2.5, 5, 7.5, 10, 15, 20, 37, 180, .greatestFiniteMagnitude, .nan] {
            XCTAssertEqual(RestScreenBreathing.opacity(at: elapsed, reduceMotion: true), 0)
        }
    }
}
