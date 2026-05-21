import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            Rectangle()
                .fill(chrome.separator.color)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSection(title: "Appearance", systemImage: "paintpalette") {
                        SettingsRow("Font") {
                            TextField("SF Mono", text: binding(\.fontFamily))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                        }

                        SettingsRow("Font Size") {
                            HStack(spacing: 10) {
                                Slider(value: binding(\.fontSize), in: 9...28, step: 1)
                                    .frame(maxWidth: 210)

                                Text("\(Int(preferencesStore.preferences.fontSize)) pt")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(chrome.secondaryText)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }

                        SettingsRow("Theme") {
                            Picker("", selection: binding(\.theme)) {
                                ForEach(TerminalTheme.allCases) { theme in
                                    Text(theme.label).tag(theme)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 210, alignment: .leading)
                        }

                        SettingsRow("Cursor") {
                            Picker("", selection: binding(\.cursorStyle)) {
                                ForEach(TerminalCursorStylePreference.allCases) { cursorStyle in
                                    Text(cursorStyle.label).tag(cursorStyle)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 210, alignment: .leading)
                        }
                    }

                    SettingsSection(title: "Terminal", systemImage: "terminal") {
                        SettingsToggleRow(
                            title: "Option Key",
                            detail: "Send Option as Meta for shell and editor shortcuts.",
                            isOn: binding(\.optionAsMetaKey)
                        )

                        SettingsToggleRow(
                            title: "Mouse Reporting",
                            detail: "Allow terminal apps to receive mouse events.",
                            isOn: binding(\.allowMouseReporting)
                        )

                        SettingsToggleRow(
                            title: "Metal Renderer",
                            detail: "Use SwiftTerm's accelerated renderer when available.",
                            isOn: binding(\.useMetalRenderer)
                        )
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 470)
        .tint(preferencesStore.preferences.theme.swiftUIAccent)
        .foregroundStyle(chrome.primaryText)
        .background {
            ZStack {
                chrome.windowBackground.color

                LinearGradient(
                    colors: [
                        chrome.headerTop.color.opacity(chrome.isLight ? 0.42 : 0.30),
                        chrome.windowBackground.color
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(chrome.iconText)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(chrome.controlFill.color)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(chrome.controlStroke.color, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(chrome.primaryText)

                Text("Keep Terminull simple, fast, and predictable.")
                    .font(.caption)
                    .foregroundStyle(chrome.tertiaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding {
            preferencesStore.preferences[keyPath: keyPath]
        } set: { newValue in
            preferencesStore.preferences[keyPath: keyPath] = newValue
        }
    }
}

private struct SettingsSection<Content: View>: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore

    let title: String
    let systemImage: String
    let content: Content

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(chrome.iconText)
                    .frame(width: 18)

                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(chrome.tertiaryText)
            }

            VStack(alignment: .leading, spacing: 11) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chrome.controlFill.color)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(chrome.controlStroke.color, lineWidth: 1)
        }
    }
}

private struct SettingsRow<Content: View>: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore

    let title: String
    let content: Content

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(chrome.secondaryText)
                .frame(width: SettingsMetrics.labelWidth, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsToggleRow: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore

    let title: String
    let detail: String
    @Binding var isOn: Bool

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(width: SettingsMetrics.labelWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(chrome.primaryText)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(chrome.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private enum SettingsMetrics {
    static let labelWidth: CGFloat = 112
}
