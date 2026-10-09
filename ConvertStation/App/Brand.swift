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
}

struct AccentButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background {
                if enabled {
                    Brand.accentGradient.opacity(configuration.isPressed ? 0.82 : 1)
                } else {
                    Color.secondary.opacity(0.35)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
