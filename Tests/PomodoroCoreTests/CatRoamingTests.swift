import XCTest
@testable import PomodoroCore

final class CatRoamingTests: XCTestCase {
    private func scene(seed: UInt64 = 42) -> CatRoamingScene {
        CatRoamingScene(screenWidth: 1280, screenHeight: 800,
                        catWidth: 280, catHeight: 180, seed: seed)
    }

    func testSamplingIsDeterministicAndIndependentOfFrameOrder() {
        let first = scene()
        let second = scene()
        for time in [0.0, 91, 4.5, 300, 0.1, 91] {
            XCTAssertEqual(first.pose(at: time), second.pose(at: time))
        }
        XCTAssertNotEqual(first.pose(at: 5), scene(seed: 99).pose(at: 5))
    }

    func testWholeSpriteStaysInBoundsAndVisitsBroadScreenArea() {
        let scene = scene()
        var minimumX = Double.infinity
        var maximumX = -Double.infinity
        var minimumY = Double.infinity
        var maximumY = -Double.infinity
        for time in stride(from: 0.0, through: scene.cycleDuration, by: 0.1) {
            let pose = scene.pose(at: time)
            XCTAssertGreaterThanOrEqual(pose.x - scene.catWidth / 2, 0)
            XCTAssertLessThanOrEqual(pose.x + scene.catWidth / 2, scene.screenWidth)
            XCTAssertGreaterThanOrEqual(pose.y - scene.catHeight / 2, 0)
            XCTAssertLessThanOrEqual(pose.y + scene.catHeight / 2, scene.screenHeight)
            minimumX = min(minimumX, pose.x)
            maximumX = max(maximumX, pose.x)
            minimumY = min(minimumY, pose.y)
            maximumY = max(maximumY, pose.y)
        }
        XCTAssertGreaterThan(maximumX - minimumX, (scene.screenWidth - scene.catWidth) * 0.75)
        XCTAssertGreaterThan(maximumY - minimumY, (scene.screenHeight - scene.catHeight) * 0.70)
    }

    func testPausesFreezeTheGaitAndWalkingFacesItsDirection() {
        let scene = scene()
        var sawPause = false
        var sawWalk = false
        var previous = scene.pose(at: 0)
        for time in stride(from: 0.05, through: scene.cycleDuration, by: 0.05) {
            let pose = scene.pose(at: time)
            XCTAssertGreaterThanOrEqual(pose.gaitTime + 0.000_001, previous.gaitTime)
            if !previous.isWalking && !pose.isWalking {
                sawPause = true
                XCTAssertEqual(pose.gaitTime, previous.gaitTime, accuracy: 0.000_001)
                XCTAssertEqual(pose.x, previous.x, accuracy: 0.000_001)
                XCTAssertEqual(pose.y, previous.y, accuracy: 0.000_001)
            }
            if previous.isWalking && pose.isWalking && abs(pose.x - previous.x) > 0.001 {
                sawWalk = true
                XCTAssertEqual(pose.facingLeft, pose.x < previous.x)
            }
            previous = pose
        }
        XCTAssertTrue(sawPause)
        XCTAssertTrue(sawWalk)
    }

    func testLoopBoundaryIsPositionAndGaitContinuous() {
        let scene = scene()
        let before = scene.pose(at: scene.cycleDuration - 0.000_001)
        let atBoundary = scene.pose(at: scene.cycleDuration)
        XCTAssertEqual(before.x, atBoundary.x, accuracy: 0.000_001)
        XCTAssertEqual(before.y, atBoundary.y, accuracy: 0.000_001)
        XCTAssertEqual(before.gaitTime, atBoundary.gaitTime, accuracy: 0.000_001)
    }

    func testTinyOrInvalidScreensFitTheCatWithoutInvalidNumbers() {
        for dimensions in [(1.0, 1.0), (80, 30), (0, -1), (.nan, .infinity)] {
            let scene = CatRoamingScene(screenWidth: dimensions.0, screenHeight: dimensions.1,
                                        catWidth: 500, catHeight: 300, seed: 0)
            for time in [0.0, 0.5, 500, 10_000] {
                let pose = scene.pose(at: time)
                XCTAssertTrue(pose.x.isFinite && pose.y.isFinite && pose.gaitTime.isFinite)
                XCTAssertGreaterThanOrEqual(pose.x - scene.catWidth / 2, -0.000_001)
                XCTAssertLessThanOrEqual(pose.x + scene.catWidth / 2, scene.screenWidth + 0.000_001)
                XCTAssertGreaterThanOrEqual(pose.y - scene.catHeight / 2, -0.000_001)
                XCTAssertLessThanOrEqual(pose.y + scene.catHeight / 2, scene.screenHeight + 0.000_001)
            }
        }
    }

    func testInvalidTimesStartAtTheInitialPoseAndHugeTimeRemainsFinite() {
        let scene = scene()
        let initial = scene.pose(at: 0)
        for time in [-1.0, .nan, .infinity, -.infinity] {
            XCTAssertEqual(scene.pose(at: time), initial)
        }
        let huge = scene.pose(at: .greatestFiniteMagnitude)
        XCTAssertTrue(huge.x.isFinite && huge.y.isFinite && huge.gaitTime.isFinite)
    }
}
