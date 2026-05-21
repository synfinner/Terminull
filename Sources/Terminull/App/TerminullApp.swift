import AppKit
import SwiftUI

struct TerminullApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var preferencesStore: PreferencesStore
    @StateObject private var connectionStore: ConnectionStore
    @StateObject private var sessionStore: TerminalSessionStore

    init() {
        let preferences = PreferencesStore()
        let connections = ConnectionStore()
        _preferencesStore = StateObject(wrappedValue: preferences)
        _connectionStore = StateObject(wrappedValue: connections)
        _sessionStore = StateObject(wrappedValue: TerminalSessionStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferencesStore)
                .environmentObject(connectionStore)
                .environmentObject(sessionStore)
                .onAppear {
                    appDelegate.sessionStore = sessionStore
                }
                .tint(preferencesStore.preferences.theme.swiftUIAccent)
                .preferredColorScheme(preferencesStore.preferences.theme.chrome.isLight ? .light : .dark)
                .frame(minWidth: 840, minHeight: 520)
                .background {
                    MainWindowAccessor { window in
                        appDelegate.configureMainWindow(window)
                    }
                }
        }
        .defaultSize(width: 960, height: 560)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Terminull") {
                    TerminullAboutPanel.show(theme: preferencesStore.preferences.theme)
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Terminal") {
                    sessionStore.openLocal()
                }
                .keyboardShortcut("t", modifiers: [.command])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") {
                    appDelegate.closeFocusedWindowOrSelectedTab()
                }
                .keyboardShortcut("w", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(preferencesStore)
                .preferredColorScheme(preferencesStore.preferences.theme.chrome.isLight ? .light : .dark)
        }
    }
}

enum MainWindowCloseDecision: Equatable {
    case allowWindowClose
    case requestApplicationTermination
}

enum MainWindowCloseBehavior {
    static func decision(isMainWindow: Bool, isQuitting: Bool) -> MainWindowCloseDecision {
        guard isMainWindow, !isQuitting else {
            return .allowWindowClose
        }

        return .requestApplicationTermination
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var sessionStore: TerminalSessionStore?
    private weak var mainWindow: NSWindow?
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func configureMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else {
            return
        }

        mainWindow = window
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        switch MainWindowCloseBehavior.decision(isMainWindow: sender === mainWindow, isQuitting: isQuitting) {
        case .allowWindowClose:
            return true
        case .requestApplicationTermination:
            NSApp.terminate(sender)
            return false
        }
    }

    func closeFocusedWindowOrSelectedTab() {
        if let keyWindow = NSApp.keyWindow, keyWindow !== mainWindow {
            keyWindow.performClose(nil)
            return
        }

        guard NSApp.keyWindow === mainWindow || NSApp.mainWindow === mainWindow else {
            return
        }

        _ = sessionStore?.closeSelectedSession()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isQuitting else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Quit Terminull?"
        alert.informativeText = "Are you sure you want to close the whole application? Active terminal sessions will be terminated."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            isQuitting = true
            return .terminateNow
        }

        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionStore?.terminateAllSessions()
        sessionStore?.shutdown()
    }
}
