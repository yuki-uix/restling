import XCTest
@testable import PomodoroCore

final class CatWindowSceneTests: XCTestCase {
    func testCatFillsTheWindowAndKeepsTheTopOfItsHeadVisible() {
        let scene = CatWindowScene(width: 1512, height: 982, imageAspectRatio: 1.15)
        let pose = scene.pose(pointerX: nil, pointerY: nil, elapsed: 0, timeSinceTouch: nil)
        XCTAssertEqual(pose.width / pose.height, 1.15, accuracy: 0.000_001)
        XCTAssertGreaterThan(pose.width, 1512 * 0.7)
        XCTAssertGreaterThan(pose.height, 982 * 0.8)
        XCTAssertGreaterThan(pose.centerY - pose.height * pose.scale / 2, 0)
        XCTAssertGreaterThan(pose.centerY + pose.height * pose.scale / 2, 982)
        XCTAssertFalse(pose.nearPointer)
        XCTAssertEqual(pose.responseProgress, 0)
    }

    func testPointerLeansTowardsTheVisitorAndClampsOutsideCoordinates() {
        let scene = CatWindowScene(width: 1440, height: 900, imageAspectRatio: 1.2)
        let left = scene.pose(pointerX: 0, pointerY: 450, elapsed: 0, timeSinceTouch: nil)
        let right = scene.pose(pointerX: 1440, pointerY: 450, elapsed: 0, timeSinceTouch: nil)
        let outside = scene.pose(pointerX: 100_000, pointerY: 450, elapsed: 0, timeSinceTouch: nil)
        XCTAssertLessThan(left.centerX, 720)
        XCTAssertGreaterThan(right.centerX, 720)
        XCTAssertLessThanOrEqual(abs(right.centerX - 720), 30)
        XCTAssertLessThanOrEqual(abs(left.rotationDegrees), 1.5)
        XCTAssertEqual(right, outside)
    }

    func testTouchBrieflyMovesCloserThenReturnsExactlyToIdle() {
        let scene = CatWindowScene(width: 1512, height: 982, imageAspectRatio: 1.15)
        let idle = scene.pose(pointerX: 756, pointerY: 491, elapsed: 1, timeSinceTouch: nil)
        let peak = scene.pose(pointerX: 756, pointerY: 491, elapsed: 1, timeSinceTouch: 0.12)
        let settled = scene.pose(pointerX: 756, pointerY: 491, elapsed: 1, timeSinceTouch: 1.8)
        XCTAssertEqual(peak.responseProgress, 1, accuracy: 0.000_001)
        XCTAssertGreaterThan(peak.scale, idle.scale)
        XCTAssertLessThan(peak.centerY, idle.centerY)
        XCTAssertEqual(settled, idle)
    }

    func testNearPointerTracksTheEstimatedFaceArea() {
        let scene = CatWindowScene(width: 1440, height: 900, imageAspectRatio: 1.2)
        let initial = scene.pose(pointerX: nil, pointerY: nil, elapsed: 0, timeSinceTouch: nil)
        let faceY = initial.centerY - initial.height * initial.scale * 0.18
        let face = scene.pose(pointerX: 720, pointerY: faceY, elapsed: 0, timeSinceTouch: nil)
        let corner = scene.pose(pointerX: 0, pointerY: 0, elapsed: 0, timeSinceTouch: nil)
        XCTAssertTrue(face.nearPointer)
        XCTAssertFalse(corner.nearPointer)
    }

    func testSmallScreensAndInvalidInputsRemainFinite() {
        for dimensions in [(1.0, 1.0), (320, 200), (Double.nan, -.infinity)] {
            let scene = CatWindowScene(width: dimensions.0, height: dimensions.1, imageAspectRatio: .nan)
            let pose = scene.pose(pointerX: .infinity, pointerY: .nan,
                                  elapsed: .infinity, timeSinceTouch: -.infinity)
            for value in [pose.centerX, pose.centerY, pose.width, pose.height,
                          pose.rotationDegrees, pose.scale, pose.responseProgress] {
                XCTAssertTrue(value.isFinite)
            }
            XCTAssertGreaterThan(pose.width, 0)
            XCTAssertGreaterThan(pose.height, 0)
            XCTAssertEqual(pose.responseProgress, 0)
        }
    }

    func testTouchAndPointerExtremesDoNotCutOffTopEdge() {
        let scene = CatWindowScene(width: 1512, height: 982, imageAspectRatio: 1)
        for pointerX in [0.0, 1512] {
            for pointerY in [0.0, 982] {
                for touch in [0.12, 0.35, 0.8, 1.4] {
                    let pose = scene.pose(pointerX: pointerX, pointerY: pointerY,
                                          elapsed: 7.2, timeSinceTouch: touch)
                    let radians = pose.rotationDegrees * .pi / 180
                    let rotatedHalfHeight = pose.height * pose.scale * cos(radians) / 2
                        + pose.width * pose.scale * abs(sin(radians)) / 2
                    XCTAssertGreaterThanOrEqual(pose.centerY - rotatedHalfHeight, 0)
                    XCTAssertLessThanOrEqual(abs(pose.rotationDegrees), 2.5)
                }
            }
        }
    }

    func testCatOccasionallyLiftsThenSettlesBackOntoTheSill() {
        let scene = CatWindowScene(width: 1512, height: 982, imageAspectRatio: 1.1)
        let atRest = scene.pose(pointerX: nil, pointerY: nil, elapsed: 0, timeSinceTouch: nil)
        let lifted = scene.pose(pointerX: nil, pointerY: nil, elapsed: 7.2, timeSinceTouch: nil)
        let settled = scene.pose(pointerX: nil, pointerY: nil, elapsed: 10.8, timeSinceTouch: nil)
        let restBottom = atRest.centerY + atRest.height * atRest.scale / 2
        let liftedBottom = lifted.centerY + lifted.height * lifted.scale / 2
        let settledBottom = settled.centerY + settled.height * settled.scale / 2
        XCTAssertEqual(restBottom - liftedBottom, 24, accuracy: 0.000_001)
        XCTAssertEqual(restBottom, settledBottom, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(abs(lifted.centerX - atRest.centerX), 0.001)
    }

    func testCuriousIdleTiltAlternatesAndTouchHasAGentleCounterTilt() {
        let scene = CatWindowScene(width: 1512, height: 982, imageAspectRatio: 1.1)
        let first = scene.pose(pointerX: nil, pointerY: nil, elapsed: 7.2, timeSinceTouch: nil)
        let second = scene.pose(pointerX: nil, pointerY: nil, elapsed: 18, timeSinceTouch: nil)
        XCTAssertEqual(first.rotationDegrees, 0.65, accuracy: 0.000_001)
        XCTAssertEqual(second.rotationDegrees, -0.65, accuracy: 0.000_001)
        let touchEarly = scene.pose(pointerX: nil, pointerY: nil, elapsed: 0, timeSinceTouch: 0.35)
        let touchLater = scene.pose(pointerX: nil, pointerY: nil, elapsed: 0, timeSinceTouch: 0.9)
        XCTAssertGreaterThan(touchEarly.rotationDegrees, 0)
        XCTAssertLessThan(touchLater.rotationDegrees, 0)
        XCTAssertLessThanOrEqual(abs(touchEarly.rotationDegrees), 2.5)
    }

    func testPortraitKittenKeepsItsPawsNearTheScreenEdge() {
        let scene = CatWindowScene(width: 1512, height: 982, imageAspectRatio: 0.82)
        let pose = scene.pose(pointerX: nil, pointerY: nil, elapsed: 0, timeSinceTouch: nil)
        let bottom = pose.centerY + pose.height * pose.scale / 2
        let top = pose.centerY - pose.height * pose.scale / 2
        XCTAssertEqual(pose.height, 982, accuracy: 0.000_001)
        XCTAssertEqual(bottom, 982 * 1.02, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(top, 982 * 0.018)
        // Wider face/chest images keep the existing deeper torso crop.
        let wide = CatWindowScene(width: 1512, height: 982, imageAspectRatio: 1.1)
            .pose(pointerX: nil, pointerY: nil, elapsed: 0, timeSinceTouch: nil)
        XCTAssertEqual(wide.centerY + wide.height * wide.scale / 2, 982 * 1.14, accuracy: 0.000_001)
    }
}
