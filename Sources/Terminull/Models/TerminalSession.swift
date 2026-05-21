import Foundation
import SwiftTerm

enum TerminalSessionState: Equatable {
    case pending
    case running
    case exited(Int32?)
}

final class TerminalSession: ObservableObject, Identifiable {
    let id: UUID
    let launch: TerminalLaunch
    let profileID: UUID?
    let isRemote: Bool
    let profile: ConnectionProfile?

    @Published var title: String
    @Published var subtitle: String
    @Published var state: TerminalSessionState = .pending
    @Published var currentDirectory: String?
    @Published var terminalSize: String = ""
    @Published var warning: String?

    var terminalView: LocalProcessTerminalView?
    var didStartProcess = false
    var isClosed = false
    lazy var processObserver = TerminalSessionProcessObserver(session: self)

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        launch: TerminalLaunch,
        profileID: UUID? = nil,
        isRemote: Bool = false,
        profile: ConnectionProfile? = nil,
        warning: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.launch = launch
        self.profileID = profileID
        self.isRemote = isRemote
        self.profile = profile
        self.warning = warning
    }

    static func sanitizedTitle(_ title: String, maxLength: Int = 160) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var result = ""
        result.reserveCapacity(min(trimmed.count, maxLength))
        for scalar in trimmed.unicodeScalars {
            guard !CharacterSet.controlCharacters.contains(scalar) else {
                continue
            }
            result.unicodeScalars.append(scalar)
            if result.count >= maxLength {
                break
            }
        }

        let sanitized = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }
}

final class TerminalSessionProcessObserver: NSObject, LocalProcessTerminalViewDelegate {
    weak var session: TerminalSession?
    weak var sessionStore: TerminalSessionStore?

    init(session: TerminalSession) {
        self.session = session
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        let terminalSize = "\(newCols)x\(newRows)"
        withSessionOnMain { session in
            if session.terminalSize != terminalSize {
                session.terminalSize = terminalSize
            }
        }
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        updateTitle(title)
    }

    func updateTitle(_ title: String) {
        guard let title = TerminalSession.sanitizedTitle(title) else {
            return
        }

        withSessionOnMain { session in
            if session.title != title {
                session.title = title
            }
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        withSessionOnMain { session in
            if session.currentDirectory != directory {
                session.currentDirectory = directory
            }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        processDidTerminate(exitCode: exitCode)
    }

    func processDidTerminate(exitCode: Int32?) {
        withSessionOnMain { [weak self] session in
            session.state = .exited(exitCode)
            self?.sessionStore?.handleProcessExit(session)
        }
    }

    private func withSessionOnMain(_ operation: @escaping (TerminalSession) -> Void) {
        guard let session else {
            return
        }

        if Thread.isMainThread {
            operation(session)
        } else {
            DispatchQueue.main.async { [weak session] in
                if let session {
                    operation(session)
                }
            }
        }
    }
}
