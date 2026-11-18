import SwiftUI
import PomodoroCore

/// Small, static pixel keepsakes drawn by the app, with a distinct miniature
/// for each achievement. Locked keepsakes remain visible as a gentle preview.
struct ForestAchievementBadge: View {
    let achievement: ForestAchievement
    let isUnlocked: Bool

    var body: some View {
        Canvas { context, size in
            let unit = max(1, floor(min(size.width, size.height) / 24))
            let origin = CGPoint(x: (size.width - unit * 24) / 2, y: (size.height - unit * 24) / 2)
            func pixel(_ x: Int, _ y: Int, _ width: Int = 1, _ height: Int = 1, _ color: Color) {
                let rect = CGRect(x: origin.x + CGFloat(x) * unit, y: origin.y + CGFloat(y) * unit,
                                  width: CGFloat(width) * unit, height: CGFloat(height) * unit)
                context.fill(Path(rect), with: .color(color))
            }
            let border = Color(red: 0.73, green: 0.76, blue: 0.58)
            let cream = Color(red: 0.95, green: 0.93, blue: 0.79)
            let green = Color(red: 0.38, green: 0.59, blue: 0.36)
            let lightGreen = Color(red: 0.59, green: 0.73, blue: 0.43)
            let deepGreen = Color(red: 0.22, green: 0.42, blue: 0.31)
            let brown = Color(red: 0.55, green: 0.42, blue: 0.29)
            let water = Color(red: 0.46, green: 0.68, blue: 0.72)
            let pink = Color(red: 0.86, green: 0.61, blue: 0.61)
            let gold = Color(red: 0.85, green: 0.66, blue: 0.30)

            // A stepped paper seal, kept on an integer grid at every size.
            pixel(5, 1, 14, 22, border)
            pixel(3, 3, 18, 18, border)
            pixel(1, 5, 22, 14, border)
            pixel(5, 2, 14, 20, cream)
            pixel(3, 5, 18, 14, cream)
            pixel(5, 4, 14, 16, cream)
            pixel(5, 18, 14, 2, lightGreen.opacity(0.35))

            func tree(_ x: Int, _ y: Int, _ tint: Color = green, _ small: Bool = false) {
                if small {
                    pixel(x, y + 1, 1, 5, brown)
                    pixel(x - 1, y - 2, 3, 4, tint)
                    pixel(x - 2, y - 1, 5, 2, tint)
                    pixel(x - 1, y - 2, 2, 1, lightGreen.opacity(0.65))
                } else {
                    pixel(x - 1, y + 1, 2, 6, brown)
                    pixel(x - 3, y - 5, 6, 7, tint)
                    pixel(x - 4, y - 3, 8, 4, tint)
                    pixel(x - 2, y - 6, 4, 2, tint)
                    pixel(x - 3, y - 4, 3, 2, lightGreen.opacity(0.75))
                }
            }
            func flower(_ x: Int, _ y: Int, _ tint: Color = pink) {
                pixel(x, y, 1, 5, deepGreen)
                pixel(x - 1, y + 3, 1, 1, green)
                pixel(x - 1, y - 1, 3, 3, tint)
                pixel(x, y, 1, 1, gold)
            }
            func island(_ x: Int, _ y: Int) {
                pixel(x - 3, y, 7, 2, brown)
                pixel(x - 2, y + 2, 5, 1, brown.opacity(0.7))
                pixel(x - 3, y - 1, 7, 1, lightGreen)
                tree(x, y - 5, green, true)
            }
            func mushroom(_ x: Int, _ y: Int, _ tint: Color) {
                pixel(x, y + 1, 2, 4, Color(red: 0.88, green: 0.82, blue: 0.65))
                pixel(x - 2, y, 6, 2, tint)
                pixel(x - 1, y - 1, 4, 1, tint)
                pixel(x, y, 1, 1, cream)
            }
            func hourglass(_ marks: Int) {
                pixel(8, 5, 8, 1, brown)
                pixel(8, 17, 8, 1, brown)
                pixel(9, 6, 1, 3, brown)
                pixel(14, 6, 1, 3, brown)
                pixel(10, 9, 1, 2, brown)
                pixel(13, 9, 1, 2, brown)
                pixel(11, 11, 2, 1, brown)
                pixel(10, 12, 1, 2, brown)
                pixel(13, 12, 1, 2, brown)
                pixel(9, 14, 1, 3, brown)
                pixel(14, 14, 1, 3, brown)
                pixel(10, 7, 4, 1, gold)
                pixel(11, 8, 2, 1, gold)
                pixel(11, 14, 2, 1, gold)
                pixel(10, 15, 4, 2, gold)
                for index in 0..<marks { pixel(10 + index * 2, 20, 1, 1, deepGreen) }
            }

            switch achievement {
            case .firstRest:
                pixel(11, 11, 2, 7, deepGreen)
                pixel(7, 8, 4, 3, green)
                pixel(9, 10, 3, 2, green)
                pixel(13, 6, 4, 3, lightGreen)
                pixel(12, 9, 3, 2, lightGreen)
                pixel(8, 18, 8, 1, brown)
            case .firstTree:
                tree(12, 11)
                flower(18, 15)
            case .flowerPath:
                flower(7, 13)
                flower(12, 10, gold)
                flower(17, 14)
            case .stream:
                tree(7, 11, green, true)
                pixel(13, 5, 3, 4, water)
                pixel(11, 9, 4, 4, water)
                pixel(13, 13, 4, 5, water)
                pixel(11, 11, 2, 1, cream)
            case .mushrooms:
                mushroom(8, 13, pink)
                mushroom(15, 10, brown)
                pixel(5, 18, 2, 1, green)
            case .fullGrove:
                tree(7, 10, lightGreen, true)
                tree(17, 10, deepGreen, true)
                tree(12, 12)
            case .newGrove:
                island(7, 16)
                island(17, 13)
                pixel(11, 16, 1, 1, gold)
                pixel(13, 15, 1, 1, gold)
            case .thirdGrove:
                island(6, 16)
                island(17, 16)
                island(12, 9)
            case .hundredRests:
                pixel(7, 6, 3, 4, gold)
                pixel(11, 12, 3, 4, green)
                pixel(16, 7, 3, 4, deepGreen)
                pixel(6, 11, 2, 2, gold)
                pixel(13, 17, 2, 2, green)
                pixel(15, 12, 2, 2, deepGreen)
            case .twoSpecies:
                tree(8, 12, green, true)
                tree(16, 12, pink, true)
            case .fourSpecies:
                tree(8, 8, green, true)
                tree(16, 8, pink, true)
                tree(8, 14, gold, true)
                tree(16, 14, deepGreen, true)
            case .sixSpecies:
                for (index, tint) in [green, deepGreen, pink, lightGreen, water, gold].enumerated() {
                    tree(6 + index % 3 * 6, 8 + index / 3 * 7, tint, true)
                }
            case .pond:
                pixel(6, 12, 12, 5, water)
                pixel(8, 11, 8, 1, water)
                pixel(8, 17, 8, 1, water)
                pixel(7, 13, 3, 1, cream.opacity(0.7))
                pixel(14, 15, 2, 1, lightGreen)
                pixel(6, 8, 1, 5, deepGreen)
                pixel(5, 7, 2, 2, brown)
                pixel(17, 7, 1, 6, deepGreen)
                pixel(17, 6, 2, 2, brown)
            case .bridge:
                pixel(10, 5, 4, 14, water)
                pixel(5, 10, 14, 2, brown)
                pixel(5, 8, 1, 5, brown)
                pixel(18, 8, 1, 5, brown)
                pixel(6, 8, 12, 1, gold)
                pixel(6, 12, 3, 2, brown)
                pixel(15, 12, 3, 2, brown)
            case .visitors:
                pixel(8, 6, 2, 6, Color.white)
                pixel(13, 5, 2, 7, Color.white)
                pixel(9, 7, 1, 4, pink)
                pixel(14, 6, 1, 4, pink)
                pixel(7, 11, 10, 6, Color.white)
                pixel(9, 17, 7, 1, Color.white)
                pixel(9, 13, 1, 1, deepGreen)
                pixel(14, 13, 1, 1, deepGreen)
                pixel(11, 15, 2, 1, pink)
                pixel(17, 15, 2, 2, Color.white)
            case .tenMinutes: hourglass(1)
            case .oneHour: hourglass(2)
            case .threeHours: hourglass(3)
            case .fourWeeks, .twelveWeeks, .twentySixWeeks:
                pixel(6, 5, 6, 13, brown)
                pixel(12, 5, 6, 13, gold)
                pixel(7, 6, 4, 11, cream)
                pixel(13, 6, 4, 11, cream)
                pixel(11, 6, 2, 12, deepGreen)
                let rows = achievement == .fourWeeks ? 1 : achievement == .twelveWeeks ? 2 : 3
                for row in 0..<rows {
                    pixel(8, 8 + row * 3, 2, 1, green)
                    pixel(14, 9 + row * 3, 2, 1, pink)
                }
                pixel(8, 19, 8, 1, lightGreen)
            case .mixedGrove:
                tree(7, 11, green, true)
                tree(17, 11, gold, true)
                tree(12, 13, pink, true)
                pixel(10, 18, 1, 1, deepGreen)
                pixel(13, 18, 1, 1, deepGreen)
            }
            if isUnlocked {
                pixel(19, 2, 1, 3, gold)
                pixel(18, 3, 3, 1, gold)
            }
        }
        .saturation(isUnlocked ? 1 : 0.48)
        .opacity(isUnlocked ? 1 : 0.82)
        .accessibilityHidden(true)
    }
}
