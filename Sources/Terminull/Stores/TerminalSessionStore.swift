import Foundation
import Darwin
import SwiftTerm

final class TerminalSessionStore: ObservableObject {
    private static let terminationGraceSeconds: TimeInterval = 2

    @Published private(set) var sessions: [TerminalSession] = []
    @Published var selectedSessionID: UUID?

    private let sshAgentService: SSHAgentManaging
    private let keychain: any KeychainManaging
    private let askPassExecutablePath: () -> String?

    init(
        sshAgentService: SSHAgentManaging = SSHAgentService(),
        keychain: any KeychainManaging = KeychainService(),
        askPassExecutablePath: @escaping () -> String? = { SSHLoginPasswordAskPass.executablePath() }
    ) {
        self.sshAgentService = sshAgentService
        self.keychain = keychain
        self.askPassExecutablePath = askPassExecutablePath
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
        let sessionID = UUID()
        let preparation = sshAgentService.prepareIdentityIfNeeded(for: profile)
        let loginPasswordPreparation = savedLoginPasswordEnvironment(for: profile, sessionID: sessionID)
        let session = TerminalSession(
            id: sessionID,
            title: profile.displayName,
            subtitle: profile.target,
            launch: .ssh(
                profile: profile,
                environment: combinedEnvironment(preparation.terminalEnvironment, loginPasswordPreparation.environment)
            ),
            profileID: profile.id,
            isRemote: true,
            profile: profile,
            warning: combinedWarning(preparation.warning, loginPasswordPreparation.warning)
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

    func handleProcessExit(_ session: TerminalSession, exitCode: Int32?) {
        deleteAskPassToken(for: session)

        if session.isRemote, exitCode != 0 {
            return
        }

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
            remove(
                session,
                terminate: true,
                opensReplacementIfEmpty: false,
                waitsForProcessExit: true
            )
        }
        selectedSessionID = nil
    }

    private func remove(
        _ session: TerminalSession,
        terminate: Bool,
        opensReplacementIfEmpty: Bool = true,
        waitsForProcessExit: Bool = false
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            return
        }

        let closedProfile = session.profile
        session.isClosed = true
        deleteAskPassToken(for: session)
        if terminate {
            terminateSessionProcess(session.terminalView, waitsForProcessExit: waitsForProcessExit)
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

    private func savedLoginPasswordEnvironment(
        for profile: ConnectionProfile,
        sessionID: UUID
    ) -> (environment: [String]?, warning: String?) {
        guard profile.storesLoginPassword else {
            return (nil, nil)
        }

        do {
            guard try keychain.readSecret(account: ConnectionSecretAccount.loginPassword(for: profile.id)) != nil else {
                return (nil, "Saved SSH login password was not found in Keychain. ssh will still start and may prompt in the terminal.")
            }
            guard let executablePath = askPassExecutablePath(),
                  FileManager.default.isExecutableFile(atPath: executablePath) else {
                return (nil, "Saved SSH login password could not be used because the Terminull executable was not found.")
            }

            let token = try SSHLoginPasswordAskPass.makeToken()
            let tokenAccount = ConnectionSecretAccount.loginPasswordAskPassToken(
                for: profile.id,
                sessionID: sessionID
            )
            try? keychain.deleteSecret(account: tokenAccount)
            try keychain.saveSecret(token, account: tokenAccount)

            return (
                SSHLoginPasswordAskPass.environment(
                    account: ConnectionSecretAccount.loginPassword(for: profile.id),
                    tokenAccount: tokenAccount,
                    token: token,
                    executablePath: executablePath
                ),
                nil
            )
        } catch {
            return (nil, "Saved SSH login password could not be read from Keychain: \(error.localizedDescription)")
        }
    }

    private func combinedEnvironment(_ first: [String]?, _ second: [String]?) -> [String]? {
        guard first != nil || second != nil else {
            return nil
        }

        var merged = TerminalEnvironment.processEnvironment()
        for variables in [first, second] {
            for variable in variables ?? [] {
                let parts = variable.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else {
                    continue
                }
                merged[String(parts[0])] = String(parts[1])
            }
        }
        return merged.isEmpty ? nil : merged.map { "\($0.key)=\($0.value)" }.sorted()
    }

    private func combinedWarning(_ first: String?, _ second: String?) -> String? {
        switch (first, second) {
        case (.some(let first), .some(let second)):
            return "\(first)\n\(second)"
        case (.some(let first), .none):
            return first
        case (.none, .some(let second)):
            return second
        case (.none, .none):
            return nil
        }
    }

    private func deleteAskPassToken(for session: TerminalSession) {
        guard let profileID = session.profileID else {
            return
        }

        try? keychain.deleteSecret(account: ConnectionSecretAccount.loginPasswordAskPassToken(
            for: profileID,
            sessionID: session.id
        ))
    }

    private func terminateSessionProcess(
        _ terminalView: LocalProcessTerminalView?,
        waitsForProcessExit: Bool = false
    ) {
        guard let terminalView else {
            return
        }

        let pid = terminalView.process.shellPid
        terminalView.terminate()

        guard pid > 0 else {
            return
        }

        if waitsForProcessExit {
            Self.killProcessGroupIfStillRunning(pid: pid, graceSeconds: Self.terminationGraceSeconds)
            return
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.terminationGraceSeconds) {
            Self.killProcessGroupIfStillRunning(pid: pid, graceSeconds: 0)
        }
    }

    private static func killProcessGroupIfStillRunning(pid: pid_t, graceSeconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(graceSeconds)
        while Date() < deadline {
            guard processIsStillRunning(pid: pid) else {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        guard processIsStillRunning(pid: pid) else {
            return
        }

        kill(-pid, SIGKILL)
        kill(pid, SIGKILL)

        var status: Int32 = 0
        _ = waitpid(pid, &status, WNOHANG)
    }

    private static func processIsStillRunning(pid: pid_t) -> Bool {
        var status: Int32 = 0
        let waitResult = waitpid(pid, &status, WNOHANG)
        if waitResult == pid {
            return false
        }
        if waitResult == -1, errno == ECHILD {
            return false
        }

        return kill(pid, 0) == 0
    }
}
