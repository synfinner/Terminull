import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var sessionStore: TerminalSessionStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    @Binding var showingConnectionEditor: Bool
    @Binding var editingProfile: ConnectionProfile?

    @State private var profilePendingDeletion: ConnectionProfile?
    @State private var hoveredProfileID: UUID?

    private var deletionConfirmationPresented: Binding<Bool> {
        Binding {
            profilePendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                profilePendingDeletion = nil
            }
        }
    }

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Spacer()

                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(chrome.iconText)
                    .frame(width: 24, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(chrome.controlFill.color)
                    }
                    .help("Sidebar")
            }
            .frame(maxWidth: .infinity, alignment: .topTrailing)
            .padding(.top, 8)
            .padding(.trailing, SidebarMetrics.rightInset)
            .frame(height: 48, alignment: .top)

            VStack(alignment: .leading, spacing: 18) {
                SidebarSection {
                    SidebarSectionLabel("Sessions")
                } content: {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sessionStore.sessions) { session in
                            SidebarSessionRow(session: session, isSelected: sessionStore.selectedSessionID == session.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    sessionStore.select(session)
                                }
                                .contextMenu {
                                    Button("Close") {
                                        sessionStore.close(session)
                                    }
                                }
                        }
                    }
                }

                SidebarSection {
                    HStack {
                        Text("SSH")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(chrome.tertiaryText)
                            .textCase(.uppercase)

                        Spacer()

                        Button {
                            editingProfile = nil
                            showingConnectionEditor = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 20, height: 20)
                                .background {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(chrome.controlFill.color)
                                }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(chrome.iconText)
                        .help("Add SSH Connection")
                    }
                } content: {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(connectionStore.profiles) { profile in
                            Button {
                                connectionStore.markConnected(profile)
                                sessionStore.openSSH(profile: profile)
                            } label: {
                                SidebarConnectionRow(profile: profile, isHovered: hoveredProfileID == profile.id)
                            }
                            .buttonStyle(.plain)
                            .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.cardRadius, style: .continuous))
                            .onHover { isHovered in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoveredProfileID = isHovered ? profile.id : nil
                                }
                            }
                            .contextMenu {
                                Button("Edit") {
                                    editingProfile = profile
                                    showingConnectionEditor = true
                                }
                                Button("Delete", role: .destructive) {
                                    profilePendingDeletion = profile
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, SidebarMetrics.leftInset)
            .padding(.trailing, SidebarMetrics.rightInset)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        chrome.sidebarTop.color.opacity(chrome.isLight ? 0.92 : 0.74),
                        chrome.sidebarBottom.color.opacity(chrome.isLight ? 0.96 : 0.90)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .alert("Delete SSH Connection?", isPresented: deletionConfirmationPresented) {
            Button("Delete", role: .destructive) {
                if let profilePendingDeletion {
                    if connectionStore.delete(profilePendingDeletion) {
                        sessionStore.closeSessions(forProfile: profilePendingDeletion)
                    }
                }
                profilePendingDeletion = nil
            }

            Button("Cancel", role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: {
            Text("Are you sure you wish to delete this connection?")
        }
    }
}

private enum SidebarMetrics {
    static let leftInset: CGFloat = 16
    static let rightInset: CGFloat = 14
    static let cardRadius: CGFloat = 6
}

private struct SidebarSection<Header: View, Content: View>: View {
    let header: Header
    let content: Content

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarSectionLabel: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(preferencesStore.preferences.theme.chrome.tertiaryText)
    }
}

private struct SidebarSessionRow: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @ObservedObject var session: TerminalSession
    let isSelected: Bool

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: session.isRemote ? "server.rack" : "terminal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? chrome.primaryText : chrome.iconText)
                .frame(width: 17)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? chrome.primaryText : chrome.primaryText.opacity(0.86))
                    .lineLimit(1)

                Text(session.subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? chrome.secondaryText : chrome.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: SidebarMetrics.cardRadius, style: .continuous)
                    .fill(chrome.selectionFill.color)
                    .overlay {
                        RoundedRectangle(cornerRadius: SidebarMetrics.cardRadius, style: .continuous)
                            .stroke(chrome.selectedStroke.color, lineWidth: 1)
                    }
            }
        }
    }
}

private struct SidebarConnectionRow: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    let profile: ConnectionProfile
    let isHovered: Bool

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: profile.identityFilePath.isEmpty ? "server.rack" : "key.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? chrome.primaryText : chrome.iconText)
                .frame(width: 17)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isHovered ? chrome.primaryText : chrome.primaryText.opacity(0.88))
                    .lineLimit(1)

                Text(profile.target)
                    .font(.caption)
                    .foregroundStyle(isHovered ? chrome.secondaryText : chrome.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: SidebarMetrics.cardRadius, style: .continuous)
                .fill(isHovered ? chrome.hoverFill.color : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: SidebarMetrics.cardRadius, style: .continuous)
                .stroke(isHovered ? chrome.selectedStroke.color : Color.clear, lineWidth: 1)
        }
    }
}
