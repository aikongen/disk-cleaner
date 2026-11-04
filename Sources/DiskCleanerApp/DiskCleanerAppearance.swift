import SwiftUI

// Product-local appearance values. The saved Appearance setting (Teal/Violet)
// chooses between them at runtime; no Info.plist key is read.
enum DiskCleanerAppearance {
    static let greenTop = Color(red: 0.12, green: 0.19, blue: 0.22)
    static let greenGlow1 = Color(red: 0.12, green: 0.36, blue: 0.39)
    static let greenGlow2 = Color(red: 0.18, green: 0.31, blue: 0.48)
    // Chief S atmosphere: ground #0B0A10, RGB 83/56/158 and 44/28/95.
    static let violetGround = Color(red: 11.0 / 255, green: 10.0 / 255, blue: 16.0 / 255)
    static let violetGlow1 = Color(red: 83.0 / 255, green: 56.0 / 255, blue: 158.0 / 255)
    static let violetGlow2 = Color(red: 44.0 / 255, green: 28.0 / 255, blue: 95.0 / 255)
}

enum Paint {
    static let background = Color(red: 0.105, green: 0.135, blue: 0.16)
    static let group = Color.white.opacity(0.055)
    static let selected = Color.white.opacity(0.12)
    static let line = Color.white.opacity(0.105)
    static let secondary = Color(red: 0.69, green: 0.73, blue: 0.76)
    static let teal = Color(red: 0.23, green: 0.70, blue: 0.65)
    static let blue = Color(red: 0.40, green: 0.60, blue: 0.86)
    static let gold = Color(red: 0.83, green: 0.66, blue: 0.28)
    static let rose = Color(red: 0.80, green: 0.51, blue: 0.61)
    static let slate = Color(red: 0.54, green: 0.61, blue: 0.69)
    static let palette = [teal, blue, gold, rose, slate]
}
