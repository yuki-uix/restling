import Foundation

/// A large photographic cat, measured in a top-left-origin window coordinate space.
/// Render width/height at the returned centre, then apply scale and rotation.
public struct CatWindowPose: Equatable, Sendable {
    public let centerX: Double
    public let centerY: Double
    public let width: Double
    public let height: Double
    public let rotationDegrees: Double
    public let scale: Double
    public let nearPointer: Bool
    /// Reaction intensity: zero at rest, one just after a touch, then gently zero.
    public let responseProgress: Double
}

/// The screen is a window through which a large cat leans towards the visitor.
/// The lower torso may extend below the screen; the head's upper edge stays visible.
/// This type contains no event handling or animation timers, so sampling is stable.
public struct CatWindowScene: Sendable {
    public let width: Double
    public let height: Double
    public let imageAspectRatio: Double

    public init(width: Double, height: Double, imageAspectRatio: Double) {
        self.width = Self.dimension(width)
        self.height = Self.dimension(height)
        self.imageAspectRatio = imageAspectRatio.isFinite && imageAspectRatio > 0
            ? min(3, max(0.35, imageAspectRatio)) : 1.15
    }

    public func pose(pointerX: Double?, pointerY: Double?, elapsed: TimeInterval,
                     timeSinceTouch: TimeInterval?) -> CatWindowPose {
        let portrait = imageAspectRatio < 0.95
        // Portrait kitten assets include real front paws. Keep almost the whole
        // image above the lower edge so they can rest in front of the window sill.
        let heroWidth = min(width * 0.78, height * (portrait ? 1.0 : 1.02) * imageAspectRatio)
        let heroHeight = heroWidth / imageAspectRatio
        let x = Self.coordinate(pointerX, maximum: width)
        let y = Self.coordinate(pointerY, maximum: height)
        let horizontal = x.map { ($0 / width - 0.5) * 2 } ?? 0
        let vertical = y.map { ($0 / height - 0.5) * 2 } ?? 0
        let time = elapsed.isFinite ? min(31_536_000, max(0, elapsed)) : 0
        let response = Self.touchEnvelope(timeSinceTouch)
        let breath = sin(time * .pi / 2.8) * 0.004
        let scale = 1 + breath + response * 0.035
        let idleCycle = floor(time / 10.8)
        let idlePhase = time.truncatingRemainder(dividingBy: 10.8)
        let idleLift: Double
        let idleTilt: Double
        if (5.8...8.6).contains(idlePhase) {
            let progress = (idlePhase - 5.8) / 2.8
            let curiosity = pow(sin(progress * .pi), 2)
            idleLift = curiosity * min(24, height * 0.026)
            idleTilt = curiosity * (idleCycle.truncatingRemainder(dividingBy: 2) == 0 ? 0.65 : -0.65)
        } else {
            idleLift = 0
            idleTilt = 0
        }

        let centerX = width / 2 + horizontal * min(30, width * 0.03)
        let touchTime = timeSinceTouch.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
        let touchWiggle = sin(min(touchTime, 1.8) / 1.8 * 2.6 * .pi) * response * 1.15
        let rotation = min(2.5, max(-2.5, horizontal * 1.35 + vertical * 0.12 + idleTilt + touchWiggle))
        // Most of the cat remains visible while the torso rests on an imaginary
        // sill just below the lower edge. Pointer motion only produces a small lean.
        let bottomAnchor = height * (portrait ? 1.02 : 1.14)
        let proposedY = bottomAnchor - heroHeight * scale / 2
            + vertical * min(16, height * 0.018) - response * min(28, height * 0.03) - idleLift
        let radians = abs(rotation) * .pi / 180
        let rotatedHalfHeight = heroHeight * scale * cos(radians) / 2
            + heroWidth * scale * sin(radians) / 2
        let centerY = max(proposedY, rotatedHalfHeight + height * 0.018)
        let faceY = centerY - heroHeight * scale * 0.18
        let nearby: Bool
        if let x, let y {
            let dx = (x - centerX) / max(0.001, heroWidth * scale * 0.36)
            let dy = (y - faceY) / max(0.001, heroHeight * scale * 0.27)
            nearby = dx * dx + dy * dy <= 1
        } else {
            nearby = false
        }

        return CatWindowPose(centerX: centerX, centerY: centerY,
            width: heroWidth, height: heroHeight,
            rotationDegrees: rotation,
            scale: scale, nearPointer: nearby, responseProgress: response)
    }

    private static func dimension(_ value: Double) -> Double {
        value.isFinite && value > 0 ? min(100_000, value) : 1
    }

    private static func coordinate(_ value: Double?, maximum: Double) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(maximum, max(0, value))
    }

    private static func touchEnvelope(_ time: TimeInterval?) -> Double {
        guard let time, time.isFinite, time >= 0, time < 1.8 else { return 0 }
        if time < 0.12 { return smoothstep(time / 0.12) }
        return 1 - smoothstep((time - 0.12) / 1.68)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let clamped = min(1, max(0, value))
        return clamped * clamped * (3 - 2 * clamped)
    }
}
