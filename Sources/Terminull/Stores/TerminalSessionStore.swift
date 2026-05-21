import Foundation
import Darwin
import SwiftTerm

final class TerminalSessionStore: ObservableObject {
    private static let terminationGraceSeconds: TimeInterval = 2

    @Published private(set) var sessions: [TerminalSession] = []
    @Published var selectedSessionID: UUID?

    private let sshAgentService: SSHAgentManaging

    init(sshAgentService: SSHAgentManaging = SSHAgentService()) {
        self.sshAgentService = sshAgentService
    }

    var selectedSession: TerminalSession? {
        sessions.first { $0.id == selectedSessionID } ?? sessions.first
    }

    func openLocal() {
        let session = TerminalSession(
            title: "Local",
            subtitle: ShellResolver.defaultShell(),
            launch: .localShell()
        )
        add(session)
    }

    func openSSH(profile: ConnectionProfile) {
        let preparation = sshAgentService.prepareIdentityIfNeeded(for: profile)
        let session = TerminalSession(
            title: profile.displayName,
            subtitle: profile.target,
            launch: .ssh(profile: profile, environment: preparation.terminalEnvironment),
            profileID: profile.id,
            isRemote: true,
            profile: profile,
            warning: preparation.warning
        )
        add(session)
    }

    func select(_ session: TerminalSession) {
        selectedSessionID = session.id
    }

    func close(_ session: TerminalSession) {
        remove(session, terminate: true)
    }

    @discardableResult
    func closeSelectedSession() -> Bool {
        guard let session = selectedSession else {
            return false
        }

        close(session)
        return true
    }

    func handleProcessExit(_ session: TerminalSession) {
        remove(session, terminate: false)
    }

    func closeSessions(forProfile profile: ConnectionProfile) {
        let sessionsToClose = sessions.filter { $0.profileID == profile.id }
        if sessionsToClose.isEmpty {
            sshAgentService.removeIdentity(for: profile)
        }

        for session in sessionsToClose {
            remove(session, terminate: true)
        }
    }

    func shutdown() {
        sshAgentService.shutdown()
    }

    func terminateAllSessions() {
        let sessionsToTerminate = sessions
        for session in sessionsToTerminate {
            remove(session, terminate: true, opensReplacementIfEmpty: false)
        }
        selectedSessionID = nil
    }

    private func remove(_ session: TerminalSession, terminate: Bool, opensReplacementIfEmpty: Bool = true) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            return
        }

        let closedProfile = session.profile
        session.isClosed = true
        if terminate {
            terminateSessionProcess(session.terminalView)
        }
        session.terminalView?.processDelegate = nil
        session.terminalView = nil
        sessions.remove(at: index)

        if selectedSessionID == session.id {
            selectedSessionID = sessions.last?.id
        }

        if sessions.isEmpty && opensReplacementIfEmpty {
            openLocal()
        }

        if let closedProfile, !sessions.contains(where: { $0.profileID == closedProfile.id }) {
            sshAgentService.removeIdentity(for: closedProfile)
        }
    }

    private func add(_ session: TerminalSession) {
        session.processObserver.sessionStore = self
        sessions.append(session)
        selectedSessionID = session.id
    }

    private func terminateSessionProcess(_ terminalView: LocalProcessTerminalView?) {
        guard let terminalView else {
            return
        }

        let pid = terminalView.process.shellPid
        terminalView.terminate()

        guard pid > 0 else {
            return
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.terminationGraceSeconds) {
            guard kill(pid, 0) == 0 else {
                return
            }

            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)

            var status: Int32 = 0
            _ = waitpid(pid, &status, WNOHANG)
        }
    }
}
