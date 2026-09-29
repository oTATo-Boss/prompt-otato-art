import SwiftUI

enum AppAccentPalette: String, CaseIterable {
    case monochrome
    case notes
}

struct AppAccentStyle {
    let palette: AppAccentPalette
    let colorScheme: ColorScheme

    private var isDark: Bool { colorScheme == .dark }

    /// The control tint is darker than the yellow selection fill in light mode,
    /// so focus rings and small symbols remain visible on white surfaces.
    var tint: Color {
        switch palette {
        case .monochrome: color(isDark ? 0xF1F1EF : 0x202020)
        case .notes: color(isDark ? 0xFFD76B : 0xA57100)
        }
    }

    var selectedFill: Color {
        switch palette {
        case .monochrome: color(isDark ? 0xF1F1EF : 0x202020)
        case .notes: color(isDark ? 0xFFD76B : 0xF6CF58)
        }
    }

    var selectedForeground: Color {
        switch palette {
        case .monochrome: color(isDark ? 0x161616 : 0xFFFFFF)
        case .notes: color(0x202020)
        }
    }

    var softSelection: Color {
        switch palette {
        case .monochrome: color(isDark ? 0x353535 : 0xF2F2F2)
        case .notes: color(isDark ? 0x463C27 : 0xFFF6DD)
        }
    }

    private func color(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: 1)
    }
}

private struct AppAccentStyleKey: EnvironmentKey {
    static let defaultValue = AppAccentStyle(palette: .monochrome, colorScheme: .light)
}

extension EnvironmentValues {
    var appAccentStyle: AppAccentStyle {
        get { self[AppAccentStyleKey.self] }
        set { self[AppAccentStyleKey.self] = newValue }
    }
}

private struct AppAccentModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("accentPalette") private var paletteRaw = AppAccentPalette.monochrome.rawValue

    private var resolvedColorScheme: ColorScheme {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: systemColorScheme
        }
    }

    func body(content: Content) -> some View {
        let style = AppAccentStyle(
            palette: AppAccentPalette(rawValue: paletteRaw) ?? .monochrome,
            colorScheme: resolvedColorScheme
        )
        content
            .environment(\.appAccentStyle, style)
            .tint(style.tint)
    }
}

extension View {
    func applyAppAccent() -> some View { modifier(AppAccentModifier()) }
}
