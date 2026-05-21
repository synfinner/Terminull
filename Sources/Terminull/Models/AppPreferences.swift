import Foundation

enum TerminalCursorStylePreference: String, Codable, CaseIterable, Identifiable {
    case blinkUnderline
    case steadyBar
    case steadyBlock
    case blinkBlock
    case steadyUnderline
    case blinkBar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blinkUnderline:
            return "Blinking Underline"
        case .steadyBlock:
            return "Block"
        case .blinkBlock:
            return "Blinking Block"
        case .steadyUnderline:
            return "Underline"
        case .steadyBar:
            return "Bar"
        case .blinkBar:
            return "Blinking Bar"
        }
    }
}

struct AppPreferences: Codable, Equatable {
    var fontFamily: String = "SF Mono"
    var fontSize: Double = 13
    var theme: TerminalTheme = .graphite
    var cursorStyle: TerminalCursorStylePreference = .blinkUnderline
    var optionAsMetaKey: Bool = true
    var allowMouseReporting: Bool = true
    var useMetalRenderer: Bool = true

    init(
        fontFamily: String = "SF Mono",
        fontSize: Double = 13,
        theme: TerminalTheme = .graphite,
        cursorStyle: TerminalCursorStylePreference = .blinkUnderline,
        optionAsMetaKey: Bool = true,
        allowMouseReporting: Bool = true,
        useMetalRenderer: Bool = true
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.theme = theme
        self.cursorStyle = cursorStyle
        self.optionAsMetaKey = optionAsMetaKey
        self.allowMouseReporting = allowMouseReporting
        self.useMetalRenderer = useMetalRenderer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "SF Mono"
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 13
        theme = try container.decodeIfPresent(TerminalTheme.self, forKey: .theme) ?? .graphite
        cursorStyle = try container.decodeIfPresent(TerminalCursorStylePreference.self, forKey: .cursorStyle) ?? .blinkUnderline
        optionAsMetaKey = try container.decodeIfPresent(Bool.self, forKey: .optionAsMetaKey) ?? true
        allowMouseReporting = try container.decodeIfPresent(Bool.self, forKey: .allowMouseReporting) ?? true
        useMetalRenderer = try container.decodeIfPresent(Bool.self, forKey: .useMetalRenderer) ?? true
    }
}
