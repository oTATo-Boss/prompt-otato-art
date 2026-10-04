import AppKit
import SwiftUI

enum AppAccentPalette: String, CaseIterable {
    case monochrome
    case notes
    case blue
}

struct AppAccentStyle {
    let palette: AppAccentPalette
    let colorScheme: ColorScheme

    private var isDark: Bool { colorScheme == .dark }

    var tint: Color { selectedFill }

    var selectedFill: Color {
        switch palette {
        case .monochrome: Color(nsColor: .labelColor)
        case .notes: Color(nsColor: .systemYellow)
        case .blue: color(0x2B5FFC)
        }
    }

    var selectedForeground: Color {
        switch palette {
        case .monochrome: Color(nsColor: .textBackgroundColor)
        case .notes: color(0x202020)
        case .blue: .white
        }
    }

    var hoverFill: Color {
        switch palette {
        case .monochrome: neutralSurface.opacity(0.65)
        case .notes: selectedFill.opacity(isDark ? 0.18 : 0.20)
        case .blue: selectedFill.opacity(isDark ? 0.24 : 0.12)
        }
    }

    // Hover uses a translucent tint; selection uses the solid palette color.
    private var neutralSurface: Color { Color(nsColor: .unemphasizedSelectedContentBackgroundColor) }
    var controlFill: Color { neutralSurface.opacity(0.40) }

    var selectionOutline: Color { selectedFill }

    /// Small accent symbols need more contrast than a large colored fill.
    var actionForeground: Color {
        switch palette {
        case .monochrome: Color(nsColor: .labelColor)
        case .notes: isDark ? Color(nsColor: .systemYellow) : color(0x8A6500)
        case .blue: isDark ? color(0x8FACFF) : color(0x2B5FFC)
        }
    }

    var focusOutline: Color { actionForeground.opacity(0.55) }

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
    func appPrimaryAction() -> some View { modifier(AppPrimaryActionModifier()) }
    func appSecondaryAction() -> some View {
        modifier(AppSecondaryActionModifier())
    }
    func appScrollEdge() -> some View { modifier(AppScrollEdgeModifier()) }

    @ViewBuilder
    func appTopBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: .top, spacing: 0, content: content)
        }
    }
}

private struct AppPrimaryActionModifier: ViewModifier {
    @Environment(\.appAccentStyle) private var accent
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .tint(accent.selectedFill)
            // Native prominent buttons lose their tint in inactive windows.
            // Their labels must follow the neutral background in that state.
            .foregroundStyle(!isEnabled ? Color(nsColor: .disabledControlTextColor)
                             : appearsActive ? accent.selectedForeground : Color.primary)
    }
}

private struct AppSecondaryActionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.bordered).tint(nil)
    }
}

private struct AppScrollEdgeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}
