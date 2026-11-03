import Foundation

/// Presentation-only dimming for the rest screen. The caller owns elapsed time,
/// so pausing, resuming and completing a rest stay with the existing timer.
/// Apply this value as a black layer's opacity: 0.12 retains 88% brightness.
public enum RestScreenBreathing: Sendable {
    public static let period: TimeInterval = 10
    public static let maximumDimming: Double = 0.12

    public static func opacity(at elapsed: TimeInterval, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion, elapsed.isFinite, elapsed >= 0 else { return 0 }
        // Reduce before multiplying to keep extreme, finite values safe. The
        // cosine also starts and ends each half-cycle at zero velocity.
        let phase = elapsed.truncatingRemainder(dividingBy: period)
        let opacity = maximumDimming * (1 - cos(2 * .pi * phase / period)) / 2
        return min(maximumDimming, max(0, opacity))
    }
}
