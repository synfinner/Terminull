import SwiftUI

private enum TerminalChrome {
    static let headerHeight: CGFloat = 52
    static let tabCornerRadius: CGFloat = 5
    static let tabStripHorizontalPadding: CGFloat = 10
    static let terminalLeadingInset: CGFloat = 6
    static let terminalTopInset: CGFloat = 5
}

struct TerminalWorkspaceView: View {
    @EnvironmentObject private var sessionStore: TerminalSessionStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    let onNewTerminal: () -> Void
    let onAddSSHConnection: () -> Void

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalHeader(onNewTerminal: onNewTerminal, onAddSSHConnection: onAddSSHConnection)

            Rectangle()
                .fill(chrome.separator.color)
                .frame(height: 1)

            TerminalTabStrip()

            Rectangle()
                .fill(chrome.separator.color.opacity(0.72))
                .frame(height: 1)

            if let session = sessionStore.selectedSession {
                VStack(spacing: 0) {
                    if let warning = session.warning {
                        WarningBanner(message: warning)
                    }

                    TerminalHostView(
                        session: session,
                        preferences: preferencesStore
                    )
                        .id(session.id)
                        .padding(.leading, TerminalChrome.terminalLeadingInset)
                        .padding(.top, TerminalChrome.terminalTopInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: preferencesStore.preferences.theme.background))
                }
            } else {
                ContentUnavailableView("No Terminal", systemImage: "terminal", description: Text("Open a local terminal or SSH connection."))
            }
        }
        .background(chrome.windowBackground.color)
    }
}

private struct TerminalHeader: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    let onNewTerminal: () -> Void
    let onAddSSHConnection: () -> Void

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("Terminull")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(chrome.primaryText)

            Spacer()

            HStack(spacing: 1) {
                Button(action: onNewTerminal) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .regular))
                        .frame(width: 32, height: 28)
                }
                .help("New Terminal")

                Button(action: onAddSSHConnection) {
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .regular))
                        .frame(width: 32, height: 28)
                }
                .help("Add SSH Connection")
            }
            .buttonStyle(.plain)
            .foregroundStyle(chrome.primaryText)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(chrome.controlFill.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(chrome.controlStroke.color)
            )
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: TerminalChrome.headerHeight)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        chrome.headerTop.color.opacity(chrome.isLight ? 0.96 : 0.88),
                        chrome.headerBottom.color.opacity(chrome.isLight ? 0.98 : 0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

private struct TerminalTabStrip: View {
    @EnvironmentObject private var sessionStore: TerminalSessionStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sessionStore.sessions) { session in
                    TerminalTabButton(session: session, isSelected: sessionStore.selectedSessionID == session.id)
                }

                Button {
                    sessionStore.openLocal()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .regular))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(chrome.iconText)
                .help("New Terminal")
            }
            .padding(.horizontal, TerminalChrome.tabStripHorizontalPadding)
            .padding(.vertical, 5)
        }
        .background {
            LinearGradient(
                colors: [
                    chrome.tabTop.color.opacity(chrome.isLight ? 0.96 : 0.92),
                    chrome.tabBottom.color.opacity(chrome.isLight ? 0.98 : 0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct TerminalTabButton: View {
    @EnvironmentObject private var sessionStore: TerminalSessionStore
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @ObservedObject var session: TerminalSession
    let isSelected: Bool

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.isRemote ? "server.rack" : "terminal")
                .font(.caption)
                .foregroundStyle(chrome.iconText)

            Text(session.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(chrome.primaryText)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)

            statusDot

            Button {
                sessionStore.close(session)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(chrome.iconText)
            .help("Close")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: TerminalChrome.tabCornerRadius, style: .continuous)
                .fill(isSelected ? chrome.selectionFill.color : chrome.controlFill.color.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TerminalChrome.tabCornerRadius, style: .continuous)
                .strokeBorder(isSelected ? chrome.selectedStroke.color : chrome.controlStroke.color.opacity(0.72))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            sessionStore.select(session)
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch session.state {
        case .pending:
            Circle().fill(.yellow).frame(width: 6, height: 6)
        case .running:
            Circle().fill(.green).frame(width: 6, height: 6)
        case .exited:
            Circle().fill(chrome.tertiaryText).frame(width: 6, height: 6)
        }
    }
}

private struct WarningBanner: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    let message: String

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(chrome.primaryText)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(chrome.warningFill.color)
    }
}
