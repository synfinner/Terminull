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

final class SSHAgentService: SSHAgentManaging {
    private static let processTimeoutSeconds: TimeInterval = 10

    private let keychain = KeychainService()
    private let agentLock = NSLock()
    private var agent: SSHAgent?

    init() {
        Self.removeStaleAskPassScripts()
        Self.removeStaleAgentSockets()
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

        guard profile.storesKeyPassphrase, keychain.hasSecret(account: profile.id.uuidString) else {
            return SSHAgentPreparation()
        }

        do {
            let agent = try ensureAgent()
            try addIdentityToAgent(keyPath: keyPath, account: profile.id.uuidString, agent: agent)
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
    }

    private func addIdentityToAgent(keyPath: String, account: String, agent: SSHAgent) throws {
        let scriptURL = try askPassScriptURL(account: account)
        defer {
            try? FileManager.default.removeItem(at: scriptURL)
        }

        var environment = agent.environment
        environment["SSH_ASKPASS"] = scriptURL.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = environment["DISPLAY"] ?? "localhost:0"

        try runSSHAdd(arguments: Self.addIdentityArguments(keyPath: keyPath), environment: environment)
    }

    private func runSSHAdd(arguments: [String], environment: [String: String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-add")
        process.arguments = arguments
        process.environment = Self.sshAddEnvironment(extra: environment)
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

        let result = try run(process: process, timeout: Self.processTimeoutSeconds, label: "ssh-add")

        if process.terminationStatus != 0 {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHAgentError(message: message.isEmpty ? "ssh-add exited with \(process.terminationStatus)" : message)
        }
    }

    private func ensureAgent() throws -> SSHAgent {
        if let agent, FileManager.default.fileExists(atPath: agent.socketPath) {
            return agent
        }

        let directory = SupportPaths.applicationSupportDirectory.appendingPathComponent("ssh-agent", isDirectory: true)
        try FileManager.default.createPrivateDirectory(at: directory)
        let socketURL = directory.appendingPathComponent("agent-\(UUID().uuidString).sock")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-agent")
        process.arguments = ["-a", socketURL.path, "-s"]
        process.environment = TerminalEnvironment.processEnvironment()

        let result = try run(process: process, timeout: Self.processTimeoutSeconds, label: "ssh-agent")

        let output = result.stdout
        if process.terminationStatus != 0 {
            let error = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHAgentError(message: error.isEmpty ? "ssh-agent exited with \(process.terminationStatus)" : error)
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

    private func askPassScriptURL(account: String) throws -> URL {
        let directory = SupportPaths.applicationSupportDirectory.appendingPathComponent("askpass", isDirectory: true)
        try FileManager.default.createPrivateDirectory(at: directory)
        let url = directory.appendingPathComponent("\(account)-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        exec /usr/bin/security find-generic-password -s \(Self.shellQuote(KeychainService.serviceName)) -a \(Self.shellQuote(account)) -w 2>/dev/null
        """
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return url
    }

    private func run(process: Process, timeout: TimeInterval, label: String) throws -> (stdout: String, stderr: String) {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let finished = DispatchSemaphore(value: 0)

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { _ in
            finished.signal()
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
        return (stdout, stderr)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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

    static func removeStaleAskPassScripts(
        directory: URL = SupportPaths.applicationSupportDirectory.appendingPathComponent("askpass", isDirectory: true)
    ) {
        removeFiles(in: directory) { $0.pathExtension == "sh" }
    }

    static func removeStaleAgentSockets(
        directory: URL = SupportPaths.applicationSupportDirectory.appendingPathComponent("ssh-agent", isDirectory: true)
    ) {
        removeFiles(in: directory) { $0.lastPathComponent.hasPrefix("agent-") && $0.pathExtension == "sock" }
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
