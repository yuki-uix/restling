import Foundation

/// A sprite's centre in the screen's local, top-left-origin coordinates.
public struct CatRoamingPose: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let facingLeft: Bool
    public let isWalking: Bool
    /// A continuous animation clock proportional to distance travelled. It is
    /// stationary during pauses, so feet do not keep walking while the cat rests.
    public let gaitTime: TimeInterval
    /// No depth scaling is applied. Render at the scene's fitted catWidth/Height.
    public let scale: Double
}

/// A seeded itinerary sampled directly from elapsed time, without a display timer
/// or accumulated per-frame position. Re-create it after the screen size changes.
public struct CatRoamingScene: Sendable {
    public let screenWidth: Double
    public let screenHeight: Double
    /// Fitted drawing dimensions, including the entire transparent sprite canvas.
    /// Use these dimensions when rendering; they also work on very small screens.
    public let catWidth: Double
    public let catHeight: Double
    public let cycleDuration: TimeInterval

    private struct Point: Sendable {
        let x: Double
        let y: Double
    }

    private struct Leg: Sendable {
        let from: Point
        let to: Point
        let startsAt: TimeInterval
        let walkDuration: TimeInterval
        let pauseDuration: TimeInterval
        let gaitStartsAt: TimeInterval
        let gaitDuration: TimeInterval
        let facingLeft: Bool
        var endsAt: TimeInterval { startsAt + walkDuration + pauseDuration }
    }

    private let legs: [Leg]
    private let cycleGaitDuration: TimeInterval

    public init(screenWidth: Double, screenHeight: Double,
                catWidth: Double, catHeight: Double, seed: UInt64) {
        let width = Self.dimension(screenWidth, fallback: 1)
        let height = Self.dimension(screenHeight, fallback: 1)
        let requestedWidth = Self.dimension(catWidth, fallback: 280)
        let requestedHeight = Self.dimension(catHeight, fallback: 180)
        let padding = min(24, min(width, height) * 0.04)
        let fit = min(1, (width - padding * 2) / requestedWidth,
                      (height - padding * 2) / requestedHeight)
        let fittedWidth = requestedWidth * fit
        let fittedHeight = requestedHeight * fit
        self.screenWidth = width
        self.screenHeight = height
        self.catWidth = fittedWidth
        self.catHeight = fittedHeight

        let left = padding + fittedWidth / 2
        let top = padding + fittedHeight / 2
        let travelWidth = max(0, width - padding * 2 - fittedWidth)
        let travelHeight = max(0, height - padding * 2 - fittedHeight)
        var random = SeededRandom(seed: seed)
        let reflected = random.unit() > 0.5
        // Broad two-dimensional routes include long sideways walks and diagonals.
        // The last waypoint returns to the first, keeping the repeat continuous.
        let normalized: [(Double, Double)] = [
            (0.08, 0.73), (0.92, 0.72), (0.72, 0.12), (0.06, 0.22),
            (0.36, 0.92), (0.91, 0.38), (0.10, 0.47), (0.73, 0.91),
            (0.95, 0.08), (0.05, 0.10), (0.30, 0.81), (0.84, 0.57)
        ]
        let points = normalized.map { unitX, unitY -> Point in
            let x = min(0.98, max(0.02, unitX + (random.unit() - 0.5) * 0.04))
            let y = min(0.98, max(0.02, unitY + (random.unit() - 0.5) * 0.04))
            return Point(x: left + (reflected ? 1 - x : x) * travelWidth,
                         y: top + y * travelHeight)
        }
        var itinerary: [Leg] = []
        var startsAt: TimeInterval = 0
        var gaitStartsAt: TimeInterval = 0
        for index in points.indices {
            let from = points[index]
            let to = points[(index + 1) % points.count]
            let distance = hypot(to.x - from.x, to.y - from.y)
            let moves = distance > 0.000_001
            // Cubic easing has a peak derivative of 1.5. This duration keeps the
            // peak walking speed at 60–82 points/sec and softly stops at each end.
            let peakSpeed = 60 + random.unit() * 22
            let walk = moves ? max(0.8, distance * 1.5 / peakSpeed) : 0
            let pause = 1.2 + random.unit() * 2.4
            let gait = moves ? distance / 65 : 0
            itinerary.append(Leg(from: from, to: to, startsAt: startsAt,
                                 walkDuration: walk, pauseDuration: pause,
                                 gaitStartsAt: gaitStartsAt, gaitDuration: gait,
                                 facingLeft: to.x < from.x))
            startsAt += walk + pause
            gaitStartsAt += gait
        }
        legs = itinerary
        cycleDuration = startsAt
        cycleGaitDuration = gaitStartsAt
    }

    public func pose(at time: TimeInterval) -> CatRoamingPose {
        // A century is more than enough for a single break, and keeps extreme
        // hostile doubles from overflowing the cycle and animation arithmetic.
        let elapsed = time.isFinite ? min(3_153_600_000, max(0, time)) : 0
        let cycles = floor(elapsed / cycleDuration)
        let local = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        let leg = legs.first(where: { local < $0.endsAt }) ?? legs[legs.count - 1]
        let intoLeg = max(0, local - leg.startsAt)
        let walking = leg.walkDuration > 0 && intoLeg < leg.walkDuration
        let fraction = leg.walkDuration > 0 ? min(1, intoLeg / leg.walkDuration) : 1
        let eased = fraction * fraction * (3 - 2 * fraction)
        return CatRoamingPose(
            x: leg.from.x + (leg.to.x - leg.from.x) * eased,
            y: leg.from.y + (leg.to.y - leg.from.y) * eased,
            facingLeft: leg.facingLeft,
            isWalking: walking,
            gaitTime: cycles * cycleGaitDuration + leg.gaitStartsAt + leg.gaitDuration * eased,
            scale: 1
        )
    }

    private static func dimension(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? min(100_000, value) : fallback
    }

    private struct SeededRandom {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func unit() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
            mixed ^= mixed >> 31
            return Double(mixed >> 11) / 9_007_199_254_740_992
        }
    }
}
