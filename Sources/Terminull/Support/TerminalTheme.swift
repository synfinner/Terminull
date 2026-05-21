import AppKit
import SwiftUI

enum TerminalTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case graphite
    case solarizedDark
    case paper
    case highContrast

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            return "System"
        case .graphite:
            return "Graphite"
        case .solarizedDark:
            return "Solarized Dark"
        case .paper:
            return "Paper"
        case .highContrast:
            return "High Contrast"
        }
    }

    var foreground: NSColor {
        switch self {
        case .system:
            return .textColor
        case .graphite:
            return NSColor(calibratedRed: 0.84, green: 0.86, blue: 0.84, alpha: 1)
        case .solarizedDark:
            return NSColor(calibratedRed: 0.51, green: 0.58, blue: 0.59, alpha: 1)
        case .paper:
            return NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.15, alpha: 1)
        case .highContrast:
            return .white
        }
    }

    var background: NSColor {
        switch self {
        case .system:
            return .textBackgroundColor
        case .graphite:
            return NSColor(calibratedRed: 0.055, green: 0.068, blue: 0.095, alpha: 1)
        case .solarizedDark:
            return NSColor(calibratedRed: 0.00, green: 0.17, blue: 0.21, alpha: 1)
        case .paper:
            return NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.89, alpha: 1)
        case .highContrast:
            return .black
        }
    }

    var accent: NSColor {
        switch self {
        case .system:
            return .controlAccentColor
        case .graphite:
            return NSColor(calibratedRed: 0.38, green: 0.82, blue: 0.60, alpha: 1)
        case .solarizedDark:
            return NSColor(calibratedRed: 0.52, green: 0.60, blue: 0.00, alpha: 1)
        case .paper:
            return NSColor(calibratedRed: 0.10, green: 0.46, blue: 0.72, alpha: 1)
        case .highContrast:
            return .systemGreen
        }
    }

    var swiftUIAccent: Color {
        Color(nsColor: accent)
    }

    var chrome: AppChromePalette {
        switch self {
        case .system, .graphite:
            return AppChromePalette(
                isLight: false,
                windowBackground: .rgb(0.055, 0.065, 0.09),
                sidebarTop: .rgb(0.11, 0.12, 0.16),
                sidebarBottom: .rgb(0.07, 0.075, 0.105),
                headerTop: .rgb(0.13, 0.13, 0.18),
                headerBottom: .rgb(0.085, 0.095, 0.13),
                tabTop: .rgb(0.13, 0.135, 0.18),
                tabBottom: .rgb(0.105, 0.115, 0.155),
                separator: .rgb(1, 1, 1, 0.10),
                controlFill: .rgb(1, 1, 1, 0.055),
                controlStroke: .rgb(1, 1, 1, 0.10),
                selectionFill: .rgb(1, 1, 1, 0.075),
                selectedStroke: .rgb(1, 1, 1, 0.08),
                hoverFill: .rgb(1, 1, 1, 0.055),
                warningFill: .rgb(1, 0.84, 0.22, 0.12)
            )
        case .solarizedDark:
            return AppChromePalette(
                isLight: false,
                windowBackground: .rgb(0.00, 0.12, 0.15),
                sidebarTop: .rgb(0.02, 0.16, 0.19),
                sidebarBottom: .rgb(0.00, 0.10, 0.13),
                headerTop: .rgb(0.03, 0.19, 0.22),
                headerBottom: .rgb(0.00, 0.14, 0.17),
                tabTop: .rgb(0.03, 0.19, 0.22),
                tabBottom: .rgb(0.01, 0.15, 0.18),
                separator: .rgb(0.55, 0.63, 0.62, 0.14),
                controlFill: .rgb(0.55, 0.63, 0.62, 0.07),
                controlStroke: .rgb(0.55, 0.63, 0.62, 0.14),
                selectionFill: .rgb(0.55, 0.63, 0.62, 0.10),
                selectedStroke: .rgb(0.55, 0.63, 0.62, 0.13),
                hoverFill: .rgb(0.55, 0.63, 0.62, 0.08),
                warningFill: .rgb(0.70, 0.62, 0.18, 0.15)
            )
        case .paper:
            return AppChromePalette(
                isLight: true,
                windowBackground: .rgb(0.91, 0.90, 0.85),
                sidebarTop: .rgb(0.95, 0.94, 0.89),
                sidebarBottom: .rgb(0.88, 0.87, 0.82),
                headerTop: .rgb(0.97, 0.96, 0.91),
                headerBottom: .rgb(0.90, 0.89, 0.84),
                tabTop: .rgb(0.94, 0.93, 0.88),
                tabBottom: .rgb(0.89, 0.88, 0.83),
                separator: .rgb(0.12, 0.13, 0.12, 0.13),
                controlFill: .rgb(1, 1, 1, 0.42),
                controlStroke: .rgb(0.12, 0.13, 0.12, 0.12),
                selectionFill: .rgb(0.12, 0.13, 0.12, 0.07),
                selectedStroke: .rgb(0.12, 0.13, 0.12, 0.10),
                hoverFill: .rgb(0.12, 0.13, 0.12, 0.055),
                warningFill: .rgb(0.96, 0.72, 0.10, 0.17)
            )
        case .highContrast:
            return AppChromePalette(
                isLight: false,
                windowBackground: .rgb(0, 0, 0),
                sidebarTop: .rgb(0.02, 0.02, 0.02),
                sidebarBottom: .rgb(0, 0, 0),
                headerTop: .rgb(0.03, 0.03, 0.03),
                headerBottom: .rgb(0, 0, 0),
                tabTop: .rgb(0.045, 0.045, 0.045),
                tabBottom: .rgb(0.01, 0.01, 0.01),
                separator: .rgb(1, 1, 1, 0.26),
                controlFill: .rgb(1, 1, 1, 0.10),
                controlStroke: .rgb(1, 1, 1, 0.24),
                selectionFill: .rgb(1, 1, 1, 0.15),
                selectedStroke: .rgb(0.38, 1, 0.42, 0.45),
                hoverFill: .rgb(1, 1, 1, 0.12),
                warningFill: .rgb(1, 0.85, 0, 0.20)
            )
        }
    }
}

struct AppChromePalette: Equatable {
    let isLight: Bool
    let windowBackground: AppChromeColor
    let sidebarTop: AppChromeColor
    let sidebarBottom: AppChromeColor
    let headerTop: AppChromeColor
    let headerBottom: AppChromeColor
    let tabTop: AppChromeColor
    let tabBottom: AppChromeColor
    let separator: AppChromeColor
    let controlFill: AppChromeColor
    let controlStroke: AppChromeColor
    let selectionFill: AppChromeColor
    let selectedStroke: AppChromeColor
    let hoverFill: AppChromeColor
    let warningFill: AppChromeColor

    var primaryText: Color {
        textColor.opacity(isLight ? 0.88 : 0.94)
    }

    var secondaryText: Color {
        textColor.opacity(isLight ? 0.64 : 0.58)
    }

    var tertiaryText: Color {
        textColor.opacity(isLight ? 0.48 : 0.46)
    }

    var iconText: Color {
        textColor.opacity(isLight ? 0.72 : 0.74)
    }

    private var textColor: Color {
        isLight ? Color.black : Color.white
    }
}

struct AppChromeColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static func rgb(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> AppChromeColor {
        AppChromeColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
