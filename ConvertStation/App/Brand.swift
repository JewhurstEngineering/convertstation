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
    static let canvas = dynamic(light: Surface.lightCanvas, dark: Surface.darkCanvas)
    static let sidebar = dynamic(light: Surface.lightSidebar, dark: Surface.darkSidebar)
    static let panel = dynamic(light: Surface.lightPanel, dark: Surface.darkPanel)
    static let hairline = dynamic(light: Surface.lightHairline, dark: Surface.darkHairline)
    static let fieldFill = dynamic(light: Surface.lightField, dark: Surface.darkField)
    static let stage = Color(red: 28 / 255, green: 28 / 255, blue: 32 / 255)

    /// The same surfaces, pinned to one scheme, for previews that should not follow the app.
    enum Surface {
        static let lightCanvas: UInt32 = 0xF5F5F7
        static let darkCanvas: UInt32 = 0x0E0824
        static let lightSidebar: UInt32 = 0xFAFAFC
        static let darkSidebar: UInt32 = 0x120B2C
        static let lightPanel: UInt32 = 0xFFFFFF
        static let darkPanel: UInt32 = 0x181134
        static let lightHairline: UInt32 = 0xE3E3E8
        static let darkHairline: UInt32 = 0x2C2548
        static let lightField: UInt32 = 0xF0F0F3
        static let darkField: UInt32 = 0x241D42

        static func canvas(_ scheme: ColorScheme) -> Color { swatch(lightCanvas, darkCanvas, scheme) }
        static func sidebar(_ scheme: ColorScheme) -> Color { swatch(lightSidebar, darkSidebar, scheme) }
        static func panel(_ scheme: ColorScheme) -> Color { swatch(lightPanel, darkPanel, scheme) }
        static func hairline(_ scheme: ColorScheme) -> Color { swatch(lightHairline, darkHairline, scheme) }
        static func field(_ scheme: ColorScheme) -> Color { swatch(lightField, darkField, scheme) }

        private static func swatch(_ light: UInt32, _ dark: UInt32, _ scheme: ColorScheme) -> Color {
            Color(nsColor: NSColor(hex: scheme == .dark ? dark : light))
        }
    }

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

/// Light, dark, or whatever System Settings is using.
enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var detail: String {
        switch self {
        case .system: "Follows the appearance in System Settings."
        case .light: "Stays light, even when the Mac is dark."
        case .dark: "Stays dark, even when the Mac is light."
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func apply() {
        let resolved = nsAppearance
        NSApp.appearance = resolved
        for window in NSApp.windows {
            window.appearance = resolved
        }
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

/// Mark plus the name, with room between them. The window title is hidden so
/// this is the only label in the toolbar.
struct ToolbarLockup: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("Mark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text("ConvertStation")
                .font(.headline)
        }
        .padding(.trailing, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("ConvertStation")
    }
}

/// The system draws "ConvertStation" beside the toolbar item. Hide that so the
/// lockup is the only title and the divider isn't pressed against the word.
struct HiddenWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .toolbar(removing: .title)
                .background(WindowTitleVisibility())
        } else {
            content.background(WindowTitleVisibility())
        }
    }
}

private struct WindowTitleVisibility: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.titleVisibility = .hidden
        }
    }
}

struct BrandLockup: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(colorScheme == .dark ? "WordmarkDark" : "WordmarkLight")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 280, maxHeight: 44)
            .accessibilityLabel("ConvertStation")
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
