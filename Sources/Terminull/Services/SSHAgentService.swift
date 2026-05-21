import Foundation
import Darwin

struct SSHAgentPreparation {
    var warning: String?
    var terminalEnvironment: [String]?
}

protocol SSHAgentManaging: AnyObject {
    func prepareIdentityIfNeeded(for profile: ConnectionProfile) -> SSHAgentPreparation
    func removeIdentity(for profile: ConnectionProfile)
    func shutdown()
}

struct SSHAgentProcessResult {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
}

typealias SSHAgentProcessRunner = (Process, TimeInterval, String, Data?) throws -> SSHAgentProcessResult

final class SSHAgentService: SSHAgentManaging {
    static let maximumUnixSocketPathLength = 100

    private static let processTimeoutSeconds: TimeInterval = 10
    private static let socketTokenLength = 8

    private let keychain: any KeychainManaging
    private let runProcess: SSHAgentProcessRunner
    private let agentLock = NSLock()
    private var agent: SSHAgent?

    init(
        keychain: any KeychainManaging = KeychainService(),
        processRunner: @escaping SSHAgentProcessRunner = SSHAgentService.run
    ) {
        self.keychain = keychain
        self.runProcess = processRunner
        Self.removeStaleAskPassScripts()
        Self.removeStaleAgentSockets()
        Self.removeStaleAgentSockets(directory: Self.fallbackAgentSocketDirectory)
        Self.removeStaleAgentSockets(directory: Self.legacyAgentSocketDirectory)
    }

    deinit {
        shutdown()
    }

    func prepareIdentityIfNeeded(for profile: ConnectionProfile) -> SSHAgentPreparation {
        agentLock.lock()
        defer {
            agentLock.unlock()
        }

        let keyPath = profile.identityFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyPath.isEmpty else {
            return SSHAgentPreparation()
        }

        guard FileManager.default.fileExists(atPath: keyPath) else {
            return SSHAgentPreparation(warning: "The selected SSH key was not found. ssh will still start and report the exact failure.")
        }

        guard profile.storesKeyPassphrase else {
            return SSHAgentPreparation()
        }

        do {
            guard let passphrase = try keychain.readSecret(account: profile.id.uuidString), !passphrase.isEmpty else {
                return SSHAgentPreparation(warning: "Saved passphrase was not found in Keychain. ssh will still start and may prompt in the terminal.")
            }
            let agent = try ensureAgent()
            try addIdentityToAgent(keyPath: keyPath, passphrase: passphrase, agent: agent)
            return SSHAgentPreparation(terminalEnvironment: TerminalEnvironment.variables(extra: agent.environment))
        } catch {
            return SSHAgentPreparation(warning: "Saved passphrase could not be added to ssh-agent: \(error.localizedDescription)")
        }
    }

    func removeIdentity(for profile: ConnectionProfile) {
        agentLock.lock()
        defer {
            agentLock.unlock()
        }

        let keyPath = profile.identityFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyPath.isEmpty, let agent else {
            return
        }
        try? runSSHAdd(arguments: Self.removeIdentityArguments(keyPath: keyPath), environment: agent.environment)
    }

    func shutdown() {
        agentLock.lock()
        defer {
            agentLock.unlock()
        }

        stopAgent()
        Self.removeStaleAskPassScripts()
        Self.removeStaleAgentSockets()
        Self.removeStaleAgentSockets(directory: Self.fallbackAgentSocketDirectory)
        Self.removeStaleAgentSockets(directory: Self.legacyAgentSocketDirectory)
    }

    private func addIdentityToAgent(keyPath: String, passphrase: String, agent: SSHAgent) throws {
        try runSSHAdd(
            arguments: Self.addIdentityArguments(keyPath: keyPath),
            environment: agent.environment,
            standardInput: Self.sshAddPassphraseInput(passphrase)
        )
    }

    private func runSSHAdd(
        arguments: [String],
        environment: [String: String],
        standardInput: Data? = nil
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-add")
        process.arguments = arguments
        process.environment = Self.sshAddEnvironment(extra: environment)

        let result = try runProcess(process, Self.processTimeoutSeconds, "ssh-add", standardInput)

        if result.terminationStatus != 0 {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHAgentError(message: message.isEmpty ? "ssh-add exited with \(result.terminationStatus)" : message)
        }
    }

    private func ensureAgent() throws -> SSHAgent {
        if let agent, FileManager.default.fileExists(atPath: agent.socketPath) {
            return agent
        }

        let socketURL = Self.agentSocketURL()
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createPrivateDirectory(at: directory)
        guard socketURL.path.utf8.count <= Self.maximumUnixSocketPathLength else {
            throw SSHAgentError(message: "ssh-agent socket path is too long")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-agent")
        process.arguments = ["-a", socketURL.path, "-s"]
        process.environment = TerminalEnvironment.processEnvironment()

        let result = try runProcess(process, Self.processTimeoutSeconds, "ssh-agent", nil)

        let output = result.stdout
        if result.terminationStatus != 0 {
            let error = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHAgentError(message: error.isEmpty ? "ssh-agent exited with \(result.terminationStatus)" : error)
        }

        let parsed = Self.parseAgentOutput(output)
        guard parsed["SSH_AUTH_SOCK"] == socketURL.path else {
            throw SSHAgentError(message: "ssh-agent returned an unexpected socket path")
        }

        let prepared = SSHAgent(
            socketPath: socketURL.path,
            pid: parsed["SSH_AGENT_PID"].flatMap(Int32.init),
            environment: parsed
        )
        agent = prepared
        return prepared
    }

    private func stopAgent() {
        guard let agent else {
            return
        }

        if let pid = agent.pid {
            kill(pid, SIGTERM)
        }
        try? FileManager.default.removeItem(atPath: agent.socketPath)
        self.agent = nil
    }

    private static func run(
        process: Process,
        timeout: TimeInterval,
        label: String,
        standardInput: Data?
    ) throws -> SSHAgentProcessResult {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let finished = DispatchSemaphore(value: 0)
        let inputPipe = standardInput.map { _ in Pipe() }

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe ?? FileHandle(forReadingAtPath: "/dev/null")
        process.terminationHandler = { _ in
            finished.signal()
        }

        if let standardInput, let inputPipe {
            inputPipe.fileHandleForWriting.write(standardInput)
            try? inputPipe.fileHandleForWriting.close()
        }
        try process.run()

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            throw SSHAgentError(message: "\(label) timed out")
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return SSHAgentProcessResult(stdout: stdout, stderr: stderr, terminationStatus: process.terminationStatus)
    }

    static func sshAddEnvironment(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        extra: [String: String]
    ) -> [String: String] {
        TerminalEnvironment.processEnvironment(baseEnvironment: baseEnvironment, extra: extra)
    }

    static func parseAgentOutput(_ output: String) -> [String: String] {
        var parsed: [String: String] = [:]
        for component in output.split(whereSeparator: { $0 == ";" || $0 == "\n" }) {
            let pair = component.trimmingCharacters(in: .whitespacesAndNewlines)
            let pieces = pair.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else {
                continue
            }
            parsed[String(pieces[0])] = String(pieces[1])
        }
        return parsed
    }

    static func addIdentityArguments(keyPath: String) -> [String] {
        ["-q", "--", keyPath]
    }

    static func removeIdentityArguments(keyPath: String) -> [String] {
        ["-q", "-d", "--", keyPath]
    }

    static func sshAddPassphraseInput(_ passphrase: String) -> Data {
        Data("\(passphrase)\n".utf8)
    }

    static func agentSocketDirectory(runtimeRoot: URL = FileManager.default.temporaryDirectory) -> URL {
        runtimeRoot.appendingPathComponent("tnl-\(getuid())", isDirectory: true)
    }

    static func agentSocketURL(
        runtimeRoot: URL = FileManager.default.temporaryDirectory,
        id: UUID = UUID()
    ) -> URL {
        let token = id.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(socketTokenLength)
        let fileName = "a-\(token).sock"
        let candidate = agentSocketDirectory(runtimeRoot: runtimeRoot)
            .appendingPathComponent(fileName, isDirectory: false)

        guard candidate.path.utf8.count > maximumUnixSocketPathLength else {
            return candidate
        }

        return fallbackAgentSocketDirectory
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func removeStaleAskPassScripts(
        directory: URL = SupportPaths.applicationSupportDirectory.appendingPathComponent("askpass", isDirectory: true)
    ) {
        removeFiles(in: directory) { $0.pathExtension == "sh" }
    }

    static func removeStaleAgentSockets(
        directory: URL = agentSocketDirectory()
    ) {
        removeFiles(in: directory) { $0.lastPathComponent.hasPrefix("agent-") && $0.pathExtension == "sock" }
        removeFiles(in: directory) { $0.lastPathComponent.hasPrefix("a-") && $0.pathExtension == "sock" }
    }

    private static var legacyAgentSocketDirectory: URL {
        SupportPaths.applicationSupportDirectory.appendingPathComponent("ssh-agent", isDirectory: true)
    }

    private static var fallbackAgentSocketDirectory: URL {
        agentSocketDirectory(runtimeRoot: URL(fileURLWithPath: "/tmp", isDirectory: true))
    }

    private static func removeFiles(in directory: URL, matching predicate: (URL) -> Bool) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls where predicate(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private struct SSHAgent {
    let socketPath: String
    let pid: Int32?
    let environment: [String: String]
}

struct SSHAgentError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
