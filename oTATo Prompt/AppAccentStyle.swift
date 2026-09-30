import AppKit
import SwiftUI

enum AppAccentPalette: String, CaseIterable {
    case monochrome
    case notes
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
        }
    }

    var selectedForeground: Color {
        switch palette {
        case .monochrome: Color(nsColor: .textBackgroundColor)
        case .notes: color(0x202020)
        }
    }

    var softSelection: Color {
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    var controlFill: Color { softSelection.opacity(0.40) }
    var hoverFill: Color { softSelection.opacity(0.65) }

    /// Small accent symbols need more contrast than a large yellow fill.
    var actionForeground: Color {
        palette == .notes ? (isDark ? Color(nsColor: .systemYellow) : color(0x8A6500))
            : Color(nsColor: .labelColor)
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

    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .tint(accent.selectedFill)
            .foregroundStyle(isEnabled ? accent.selectedForeground
                             : Color(nsColor: .disabledControlTextColor))
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
