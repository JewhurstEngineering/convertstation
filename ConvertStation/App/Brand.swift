import AppKit
import SwiftUI

enum Brand {
    static let navy = Color(red: 14 / 255, green: 8 / 255, blue: 36 / 255)
    static let blue = Color(red: 46 / 255, green: 107 / 255, blue: 255 / 255)
    static let violet = Color(red: 123 / 255, green: 44 / 255, blue: 255 / 255)
    static let magenta = Color(red: 224 / 255, green: 21 / 255, blue: 128 / 255)
    static let orange = Color(red: 255 / 255, green: 90 / 255, blue: 31 / 255)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [magenta, orange], startPoint: .leading, endPoint: .trailing)
    }

    // Surfaces. Dark mode sits on the navy ground instead of system grey.
    static let canvas = dynamic(light: 0xF5F5F7, dark: 0x0E0824)
    static let sidebar = dynamic(light: 0xFAFAFC, dark: 0x120B2C)
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x181134)
    static let hairline = dynamic(light: 0xE3E3E8, dark: 0x2C2548)
    static let fieldFill = dynamic(light: 0xF0F0F3, dark: 0x241D42)
    static let stage = Color(red: 28 / 255, green: 28 / 255, blue: 32 / 255)

    // Status colors are darkened in light mode so small text stays above 4.5:1.
    static let success = dynamic(light: 0x1D7A3A, dark: 0x5BD08A)
    static let successFill = dynamic(light: 0xE3F4E8, dark: 0x15361F)
    static let warning = dynamic(light: 0xA15C00, dark: 0xF2A852)
    static let warningFill = dynamic(light: 0xFFF6EA, dark: 0x33240F)
    static let warningStroke = dynamic(light: 0xF3D9B4, dark: 0x6B4A1E)
    static let warningText = dynamic(light: 0x5E4A2F, dark: 0xE8D3B5)
    static let danger = dynamic(light: 0xB3261E, dark: 0xFF7A70)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct AccentButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background {
                if enabled {
                    Brand.accentGradient.opacity(configuration.isPressed ? 0.82 : 1)
                } else {
                    Color.secondary.opacity(0.22)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
