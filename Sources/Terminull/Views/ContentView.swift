import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var sessionStore: TerminalSessionStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    @State private var showingConnectionEditor = false
    @State private var editingProfile: ConnectionProfile?

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                showingConnectionEditor: $showingConnectionEditor,
                editingProfile: $editingProfile
            )
            .frame(width: 252)

            Rectangle()
                .fill(chrome.separator.color)
                .frame(width: 1)

            TerminalWorkspaceView(
                onNewTerminal: {
                    sessionStore.openLocal()
                },
                onAddSSHConnection: {
                    editingProfile = nil
                    showingConnectionEditor = true
                }
            )
        }
        .background(chrome.windowBackground.color)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            if sessionStore.sessions.isEmpty {
                sessionStore.openLocal()
            }
        }
        .sheet(isPresented: $showingConnectionEditor) {
            ConnectionEditorView(profile: editingProfile)
                .environmentObject(connectionStore)
                .environmentObject(preferencesStore)
        }
    }
}
