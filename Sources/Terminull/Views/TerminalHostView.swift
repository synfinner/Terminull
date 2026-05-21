import AppKit
import SwiftTerm
import SwiftUI

struct TerminalHostView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    @ObservedObject var preferences: PreferencesStore

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = session.terminalView ?? ClickableLocalProcessTerminalView(frame: .zero)
        session.terminalView = terminalView
        terminalView.processDelegate = session.processObserver
        (terminalView as? ClickableLocalProcessTerminalView)?.installClickableCursorMonitor()
        terminalView.autoresizingMask = [.width, .height]
        installRemoteOutputGuards(on: terminalView)
        configure(terminalView, coordinator: context.coordinator)
        startIfReady(terminalView)

        return terminalView
    }

    func updateNSView(_ terminalView: LocalProcessTerminalView, context: Context) {
        terminalView.processDelegate = session.processObserver
        installRemoteOutputGuards(on: terminalView)
        configure(terminalView, coordinator: context.coordinator)
        startIfReady(terminalView)
    }

    private func configure(_ terminalView: LocalProcessTerminalView, coordinator: Coordinator) {
        let appPreferences = preferences.preferences
        let configuration = TerminalRenderConfiguration(preferences: appPreferences)
        guard coordinator.appliedConfiguration != configuration else {
            return
        }
        coordinator.appliedConfiguration = configuration

        let fontSize = max(9, min(28, appPreferences.fontSize))
        terminalView.font = NSFont(name: appPreferences.fontFamily, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let theme = appPreferences.theme
        terminalView.nativeForegroundColor = theme.foreground
        terminalView.nativeBackgroundColor = theme.background
        terminalView.layer?.backgroundColor = theme.background.cgColor
        terminalView.caretColor = theme.accent
        terminalView.terminal.setCursorStyle(appPreferences.cursorStyle.swiftTermCursorStyle)
        terminalView.optionAsMetaKey = appPreferences.optionAsMetaKey
        terminalView.allowMouseReporting = appPreferences.allowMouseReporting

        do {
            try terminalView.setUseMetal(appPreferences.useMetalRenderer)
        } catch {
            NSLog("Terminull could not configure Metal renderer: \(error.localizedDescription)")
        }
    }

    private func startIfReady(_ terminalView: LocalProcessTerminalView) {
        guard !session.didStartProcess, !session.isClosed, session.terminalView === terminalView else {
            return
        }

        guard terminalView.bounds.width > 0, terminalView.bounds.height > 0 else {
            DispatchQueue.main.async { [weak session, weak terminalView] in
                guard let session, let terminalView else {
                    return
                }
                if !session.didStartProcess,
                   !session.isClosed,
                   session.terminalView === terminalView,
                   terminalView.bounds.width > 0,
                   terminalView.bounds.height > 0 {
                    startIfReady(terminalView)
                }
            }
            return
        }

        guard !session.isClosed, session.terminalView === terminalView else {
            return
        }

        session.didStartProcess = true
        session.state = .running
        terminalView.startProcess(
            executable: session.launch.executable,
            args: session.launch.args,
            environment: session.launch.environment,
            execName: session.launch.execName,
            currentDirectory: session.launch.currentDirectory
        )
        focus(terminalView)
    }

    private func focus(_ terminalView: LocalProcessTerminalView) {
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }

    private func installRemoteOutputGuards(on terminalView: LocalProcessTerminalView) {
        terminalView.linkReporting = .none
        terminalView.terminal.registerOscHandler(code: 0) { [weak session] data in
            session?.processObserver.updateTitle(String(bytes: data, encoding: .utf8) ?? "")
        }
        terminalView.terminal.registerOscHandler(code: 1) { _ in }
        terminalView.terminal.registerOscHandler(code: 2) { [weak session] data in
            session?.processObserver.updateTitle(String(bytes: data, encoding: .utf8) ?? "")
        }
        terminalView.terminal.registerOscHandler(code: 52) { _ in }
    }

    final class Coordinator: NSObject {
        var appliedConfiguration: TerminalRenderConfiguration?
    }
}

struct TerminalRenderConfiguration: Equatable {
    let fontFamily: String
    let fontSize: Double
    let theme: TerminalTheme
    let cursorStyle: TerminalCursorStylePreference
    let optionAsMetaKey: Bool
    let allowMouseReporting: Bool
    let useMetalRenderer: Bool

    init(preferences: AppPreferences) {
        fontFamily = preferences.fontFamily
        fontSize = max(9, min(28, preferences.fontSize))
        theme = preferences.theme
        cursorStyle = preferences.cursorStyle
        optionAsMetaKey = preferences.optionAsMetaKey
        allowMouseReporting = preferences.allowMouseReporting
        useMetalRenderer = preferences.useMetalRenderer
    }
}

private extension TerminalCursorStylePreference {
    var swiftTermCursorStyle: CursorStyle {
        switch self {
        case .steadyBar:
            return .steadyBar
        case .blinkBar:
            return .blinkBar
        case .steadyBlock:
            return .steadyBlock
        case .blinkBlock:
            return .blinkBlock
        case .steadyUnderline:
            return .steadyUnderline
        case .blinkUnderline:
            return .blinkUnderline
        }
    }
}
