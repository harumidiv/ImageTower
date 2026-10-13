import SwiftUI
import UIKit

enum ImageTowerTheme {
    static let background = Color(red: 0.965, green: 0.95, blue: 0.915)
    static let sky = Color(red: 0.74, green: 0.90, blue: 0.98)
    static let skyDeep = Color(red: 0.48, green: 0.78, blue: 0.93)
    static let cream = Color(red: 1.00, green: 0.97, blue: 0.88)
    static let paper = Color(red: 1.00, green: 0.995, blue: 0.97)
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.18)
    static let secondaryText = Color(red: 0.38, green: 0.43, blue: 0.44)
    static let coral = Color(red: 1.00, green: 0.39, blue: 0.28)
    static let orange = coral
    static let yellow = Color(red: 1.00, green: 0.78, blue: 0.24)
    static let mint = Color(red: 0.54, green: 0.85, blue: 0.68)
    static let pink = Color(red: 0.94, green: 0.34, blue: 0.48)
    static let purple = Color(red: 0.48, green: 0.36, blue: 0.86)

    static let uiSky = UIColor(red: 0.74, green: 0.90, blue: 0.98, alpha: 1)
    static let uiSkyDeep = UIColor(red: 0.48, green: 0.78, blue: 0.93, alpha: 1)
    static let uiInk = UIColor(red: 0.12, green: 0.16, blue: 0.18, alpha: 1)
    static let uiCoral = UIColor(red: 1.00, green: 0.39, blue: 0.28, alpha: 1)
}

struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
