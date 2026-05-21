import AppKit
import XCTest
@testable import Terminull

final class TerminalLaunchTests: XCTestCase {
    func testDefaultCursorStyleUsesBlinkingUnderline() {
        XCTAssertEqual(AppPreferences().cursorStyle, .blinkUnderline)
    }

    func testPreferencesDecodeMissingCursorStyleUsesBlinkingUnderline() throws {
        let data = """
        {
          "fontFamily": "SF Mono",
          "fontSize": 13,
          "theme": "graphite",
          "optionAsMetaKey": true,
          "allowMouseReporting": true,
          "useMetalRenderer": true
        }
        """.data(using: .utf8)!

        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(preferences.cursorStyle, .blinkUnderline)
    }

    func testThemesExposeDistinctAppChromePalettes() {
        XCTAssertFalse(TerminalTheme.graphite.chrome.isLight)
        XCTAssertTrue(TerminalTheme.paper.chrome.isLight)
        XCTAssertNotEqual(TerminalTheme.graphite.chrome.windowBackground, TerminalTheme.paper.chrome.windowBackground)
        XCTAssertNotEqual(TerminalTheme.graphite.chrome.sidebarTop, TerminalTheme.solarizedDark.chrome.sidebarTop)
    }

    func testReleaseMetadataIncludesVersionAboutCopyAndDonationAddresses() {
        XCTAssertEqual(TerminullReleaseMetadata.version, "0.1.2")
        XCTAssertTrue(TerminullReleaseMetadata.aboutText.contains("Terminull was built by synfinner. No tracking, no bs, just a terminal emulator with SSH management."))
        XCTAssertTrue(TerminullReleaseMetadata.donationText.contains("Donations are accepted via Bitcoin and Bitcoin Lightning."))
        XCTAssertEqual(TerminullReleaseMetadata.bitcoinAddress, "bc1qqfrapakl4yceqs99k84j3tznjsa9c59mklvsvm")
        XCTAssertEqual(TerminullReleaseMetadata.lightningAddress, "synfinner@cake.cash")
        XCTAssertTrue(TerminullReleaseMetadata.donationText.contains(TerminullReleaseMetadata.bitcoinAddress))
        XCTAssertTrue(TerminullReleaseMetadata.donationText.contains(TerminullReleaseMetadata.lightningAddress))
    }

    func testConnectionTargetUsesUserWhenPresent() {
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy")

        XCTAssertEqual(profile.target, "deploy@example.com")
    }

    func testConnectionTargetOmitsEmptyUser() {
        let profile = ConnectionProfile(name: "Bastion", host: "bastion.internal", username: "")

        XCTAssertEqual(profile.target, "bastion.internal")
    }

    func testSSHLaunchUsesSystemOpenSSHWithoutOpenSSHKeychainStorage() {
        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            port: 2222,
            identityFilePath: "/Users/test/.ssh/id_ed25519",
            storesKeyPassphrase: true
        )

        let launch = TerminalLaunch.ssh(profile: profile)

        XCTAssertEqual(launch.executable, "/usr/bin/ssh")
        XCTAssertTrue(launch.args.contains("-tt"))
        XCTAssertTrue(launch.args.contains("ServerAliveInterval=30"))
        XCTAssertTrue(launch.args.contains("AddKeysToAgent=no"))
        XCTAssertTrue(launch.args.contains("UseKeychain=no"))
        XCTAssertFalse(launch.args.contains("AddKeysToAgent=yes"))
        XCTAssertFalse(launch.args.contains("UseKeychain=yes"))
        XCTAssertTrue(launch.args.contains("IdentitiesOnly=yes"))
        XCTAssertTrue(launch.args.contains("/Users/test/.ssh/id_ed25519"))
        XCTAssertTrue(launch.args.contains("deploy@example.com"))
        XCTAssertTrue(launch.args.contains("2222"))
        XCTAssertEqual(launch.args.suffix(2), ["--", "deploy@example.com"])
        XCTAssertEqual(launch.startupMessage, "Connecting to deploy@example.com:2222...\r\n")
    }

    func testSSHLaunchTerminatesOptionsBeforeHost() {
        let profile = ConnectionProfile(
            name: "Suspicious",
            host: "-oProxyCommand=open /Applications/Calculator.app",
            username: ""
        )

        let launch = TerminalLaunch.ssh(profile: profile)

        XCTAssertEqual(launch.executable, "/usr/bin/ssh")
        XCTAssertEqual(launch.args.suffix(2), ["--", "-oProxyCommand=open /Applications/Calculator.app"])
    }

    func testSSHLaunchPassesPreparedAgentEnvironment() {
        let environment = ["SSH_AUTH_SOCK=/private/var/run/com.synfinner.Terminull/agent.sock"]
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy")

        let launch = TerminalLaunch.ssh(profile: profile, environment: environment)

        XCTAssertEqual(launch.environment, environment)
    }

    func testSSHAddEnvironmentDoesNotInheritAttackerAgentSocket() {
        let environment = SSHAgentService.sshAddEnvironment(
            baseEnvironment: [
                "HOME": "/Users/test",
                "USER": "test",
                "SSH_AUTH_SOCK": "/tmp/attacker.sock"
            ],
            extra: [
                "SSH_AUTH_SOCK": "/private/var/run/com.synfinner.Terminull/agent.sock"
            ]
        )

        XCTAssertEqual(environment["SSH_AUTH_SOCK"], "/private/var/run/com.synfinner.Terminull/agent.sock")
        XCTAssertEqual(environment["HOME"], "/Users/test")
    }

    func testTerminalEnvironmentOmitsInheritedAgentSocketWithoutExplicitExtra() {
        let environment = TerminalEnvironment.processEnvironment(
            baseEnvironment: [
                "HOME": "/Users/test",
                "USER": "test",
                "SSH_AUTH_SOCK": "/tmp/attacker.sock"
            ]
        )

        XCTAssertNil(environment["SSH_AUTH_SOCK"])
    }

    func testSSHAgentOutputParsingExtractsSocketAndPid() {
        let output = """
        SSH_AUTH_SOCK=/private/var/run/com.synfinner.Terminull/agent.sock; export SSH_AUTH_SOCK;
        SSH_AGENT_PID=12345; export SSH_AGENT_PID;
        echo Agent pid 12345;
        """

        let parsed = SSHAgentService.parseAgentOutput(output)

        XCTAssertEqual(parsed["SSH_AUTH_SOCK"], "/private/var/run/com.synfinner.Terminull/agent.sock")
        XCTAssertEqual(parsed["SSH_AGENT_PID"], "12345")
    }

    func testSSHAddArgumentsTerminateOptionsBeforeKeyPath() {
        let keyPath = "-oProxyCommand=open /Applications/Calculator.app"

        XCTAssertEqual(SSHAgentService.addIdentityArguments(keyPath: keyPath), ["-q", "--", keyPath])
        XCTAssertEqual(SSHAgentService.removeIdentityArguments(keyPath: keyPath), ["-q", "-d", "--", keyPath])
    }

    func testStoredPassphraseIsReadBeforeSSHAddAndPassedThroughStandardInput() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let keyURL = temporaryDirectory.appendingPathComponent("id_ed25519")
        FileManager.default.createFile(atPath: keyURL.path, contents: Data("key".utf8))
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            identityFilePath: keyURL.path,
            storesKeyPassphrase: true
        )
        let keychain = SpyKeychainStore()
        keychain.secrets[profile.id.uuidString] = "stored-passphrase"
        var events: [String] = []
        keychain.onRead = {
            events.append("keychain-read")
        }
        var sshAddInput: Data?

        let service = SSHAgentService(keychain: keychain) { process, _, _, standardInput in
            switch process.executableURL?.path {
            case "/usr/bin/ssh-agent":
                events.append("ssh-agent")
                let socketPath = process.arguments?[1] ?? "/tmp/tnl-test/a-test.sock"
                return SSHAgentProcessResult(
                    stdout: "SSH_AUTH_SOCK=\(socketPath); export SSH_AUTH_SOCK;\nSSH_AGENT_PID=12345; export SSH_AGENT_PID;\n",
                    stderr: "",
                    terminationStatus: 0
                )
            case "/usr/bin/ssh-add":
                events.append("ssh-add")
                sshAddInput = standardInput
                XCTAssertNil(process.environment?["SSH_ASKPASS"])
                XCTAssertNil(process.environment?["SSH_ASKPASS_REQUIRE"])
                return SSHAgentProcessResult(stdout: "", stderr: "", terminationStatus: 0)
            default:
                XCTFail("Unexpected process: \(process.executableURL?.path ?? "nil")")
                return SSHAgentProcessResult(stdout: "", stderr: "", terminationStatus: 1)
            }
        }

        let preparation = service.prepareIdentityIfNeeded(for: profile)

        XCTAssertNil(preparation.warning)
        XCTAssertEqual(events, ["keychain-read", "ssh-agent", "ssh-add"])
        XCTAssertEqual(sshAddInput, Data("stored-passphrase\n".utf8))
        XCTAssertNotNil(preparation.terminalEnvironment?.first { $0.hasPrefix("SSH_AUTH_SOCK=") })
    }

    func testSSHAgentSocketPathUsesShortRuntimeLocation() {
        let socketURL = SSHAgentService.agentSocketURL(
            runtimeRoot: URL(fileURLWithPath: "/var/folders/v7/f56440p13y75ndcywg8300sh0000gn/T", isDirectory: true),
            id: UUID(uuidString: "37D02F08-F234-4FF9-AA71-B07287079B99")!
        )

        XCTAssertLessThanOrEqual(socketURL.path.utf8.count, SSHAgentService.maximumUnixSocketPathLength)
        XCTAssertFalse(socketURL.path.contains("Application Support"))
        XCTAssertEqual(socketURL.lastPathComponent, "a-37d02f08.sock")
    }

    func testSSHAgentSocketPathFallsBackWhenRuntimePathIsTooLong() {
        let longRuntimeRoot = URL(
            fileURLWithPath: "/tmp/" + String(repeating: "nested-runtime-path/", count: 8),
            isDirectory: true
        )

        let socketURL = SSHAgentService.agentSocketURL(
            runtimeRoot: longRuntimeRoot,
            id: UUID(uuidString: "37D02F08-F234-4FF9-AA71-B07287079B99")!
        )

        XCTAssertLessThanOrEqual(socketURL.path.utf8.count, SSHAgentService.maximumUnixSocketPathLength)
        XCTAssertTrue(socketURL.path.hasPrefix("/tmp/tnl-"))
        XCTAssertEqual(socketURL.lastPathComponent, "a-37d02f08.sock")
    }

    func testShellResolverUsesApprovedLoginShell() {
        XCTAssertEqual(
            ShellResolver.defaultShell(loginShell: "/bin/zsh", allowedShells: ["/bin/zsh", "/bin/bash"]),
            "/bin/zsh"
        )
    }

    func testShellResolverRejectsUnapprovedExecutableShell() {
        let temporaryShell = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: temporaryShell.path, contents: Data("#!/bin/sh\n".utf8))
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryShell.path)
        defer {
            try? FileManager.default.removeItem(at: temporaryShell)
        }

        XCTAssertEqual(
            ShellResolver.defaultShell(loginShell: temporaryShell.path, allowedShells: ["/bin/zsh", "/bin/bash"]),
            "/bin/zsh"
        )
    }

    func testOpenSSHUsesPreparedAgentEnvironment() {
        let spy = SpySSHAgentService(
            preparation: SSHAgentPreparation(terminalEnvironment: ["SSH_AUTH_SOCK=/tmp/terminull-agent.sock"])
        )
        let store = TerminalSessionStore(sshAgentService: spy)
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy")

        store.openSSH(profile: profile)

        XCTAssertEqual(store.sessions.first?.launch.environment, ["SSH_AUTH_SOCK=/tmp/terminull-agent.sock"])
    }

    func testClosingProfileSessionsRemovesIdentityAndStartsReplacementIfNeeded() {
        let spy = SpySSHAgentService()
        let store = TerminalSessionStore(sshAgentService: spy)
        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            identityFilePath: "/Users/test/.ssh/id_ed25519"
        )

        store.openSSH(profile: profile)
        store.closeSessions(forProfile: profile)

        XCTAssertEqual(spy.removedProfileIDs, [profile.id])
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertNil(store.sessions.first?.profileID)
    }

    func testClosingOneOfMultipleProfileSessionsKeepsIdentityUntilLastSessionCloses() {
        let spy = SpySSHAgentService()
        let store = TerminalSessionStore(sshAgentService: spy)
        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            identityFilePath: "/Users/test/.ssh/id_ed25519"
        )

        store.openSSH(profile: profile)
        let first = store.sessions[0]
        store.openSSH(profile: profile)
        let second = store.sessions[1]

        store.close(first)
        XCTAssertEqual(spy.removedProfileIDs, [])

        store.close(second)
        XCTAssertEqual(spy.removedProfileIDs, [profile.id])
    }

    func testHiddenSessionObserverProcessExitRemovesSession() {
        let spy = SpySSHAgentService()
        let store = TerminalSessionStore(sshAgentService: spy)
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy")
        store.openLocal()
        let local = store.sessions[0]
        store.openSSH(profile: profile)
        let remote = store.sessions[1]
        store.select(local)

        remote.processObserver.processDidTerminate(exitCode: 0)

        XCTAssertEqual(store.sessions.map(\.id), [local.id])
    }

    func testTerminalTitleFromRemoteOutputIsSanitizedAndBounded() {
        let oversized = String(repeating: "A", count: 300)
        let title = TerminalSession.sanitizedTitle("\u{001B}]2;\(oversized)\u{0007}", maxLength: 24)

        XCTAssertEqual(title, "]2;\(String(repeating: "A", count: 21))")
    }

    func testSessionStoreShutdownStopsAgentService() {
        let spy = SpySSHAgentService()
        let store = TerminalSessionStore(sshAgentService: spy)

        store.shutdown()

        XCTAssertEqual(spy.shutdownCallCount, 1)
    }

    func testTerminateAllSessionsClosesWithoutOpeningReplacement() {
        let spy = SpySSHAgentService()
        let store = TerminalSessionStore(sshAgentService: spy)
        store.openLocal()
        store.openLocal()
        let sessionsToClose = store.sessions

        store.terminateAllSessions()

        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.selectedSessionID)
        XCTAssertEqual(spy.shutdownCallCount, 0)
        XCTAssertTrue(sessionsToClose.allSatisfy(\.isClosed))
    }

    func testClickableCursorMovementUsesRepeatedArrowSequences() {
        XCTAssertEqual(
            ClickableTerminalCursorMovement.arrowBytes(fromColumn: 8, toColumn: 3, applicationCursor: false),
            Array(repeating: [UInt8]([0x1b, 0x5b, 0x44]), count: 5).flatMap { $0 }
        )
        XCTAssertEqual(
            ClickableTerminalCursorMovement.arrowBytes(fromColumn: 2, toColumn: 5, applicationCursor: true),
            Array(repeating: [UInt8]([0x1b, 0x4f, 0x43]), count: 3).flatMap { $0 }
        )
        XCTAssertEqual(
            ClickableTerminalCursorMovement.arrowBytes(fromColumn: 4, toColumn: 4, applicationCursor: false),
            []
        )
    }

    func testClickableCursorMovementUsesLineEditorControlsAtLineEdges() {
        XCTAssertEqual(
            ClickableTerminalCursorMovement.movementBytes(
                fromColumn: 8,
                toColumn: 0,
                columnCount: 80,
                applicationCursor: false
            ),
            [0x01]
        )
        XCTAssertEqual(
            ClickableTerminalCursorMovement.movementBytes(
                fromColumn: 8,
                toColumn: 79,
                columnCount: 80,
                applicationCursor: false
            ),
            [0x05]
        )
    }

    func testClickableCursorMovementTreatsClicksOutsideContentAsLineEdges() {
        XCTAssertEqual(
            ClickableTerminalCursorMovement.targetColumn(
                clickedColumn: 18,
                columnCount: 80,
                contentRange: 0...12
            ),
            79
        )
        XCTAssertEqual(
            ClickableTerminalCursorMovement.targetColumn(
                clickedColumn: -2,
                columnCount: 80,
                contentRange: 4...12
            ),
            0
        )
        XCTAssertEqual(
            ClickableTerminalCursorMovement.targetColumn(
                clickedColumn: 8,
                columnCount: 80,
                contentRange: 4...12
            ),
            8
        )
    }

    func testClickableCursorMovementOnlyAllowsSameRowNormalScreenClicks() {
        XCTAssertTrue(
            ClickableTerminalCursorMovement.shouldHandle(
                clickCount: 1,
                modifierFlags: [],
                isAlternateScreen: false,
                isMouseReportingActive: false,
                clickedRow: 8,
                cursorRow: 8
            )
        )
        XCTAssertFalse(
            ClickableTerminalCursorMovement.shouldHandle(
                clickCount: 2,
                modifierFlags: [],
                isAlternateScreen: false,
                isMouseReportingActive: false,
                clickedRow: 8,
                cursorRow: 8
            )
        )
        XCTAssertFalse(
            ClickableTerminalCursorMovement.shouldHandle(
                clickCount: 1,
                modifierFlags: [.shift],
                isAlternateScreen: false,
                isMouseReportingActive: false,
                clickedRow: 8,
                cursorRow: 8
            )
        )
        XCTAssertFalse(
            ClickableTerminalCursorMovement.shouldHandle(
                clickCount: 1,
                modifierFlags: [],
                isAlternateScreen: true,
                isMouseReportingActive: false,
                clickedRow: 8,
                cursorRow: 8
            )
        )
        XCTAssertFalse(
            ClickableTerminalCursorMovement.shouldHandle(
                clickCount: 1,
                modifierFlags: [],
                isAlternateScreen: false,
                isMouseReportingActive: true,
                clickedRow: 8,
                cursorRow: 8
            )
        )
        XCTAssertFalse(
            ClickableTerminalCursorMovement.shouldHandle(
                clickCount: 1,
                modifierFlags: [],
                isAlternateScreen: false,
                isMouseReportingActive: false,
                clickedRow: 7,
                cursorRow: 8
            )
        )
    }

    func testStaleAskPassScriptsAreRemoved() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let staleScript = temporaryDirectory.appendingPathComponent("stale.sh")
        let unrelated = temporaryDirectory.appendingPathComponent("notes.txt")
        FileManager.default.createFile(atPath: staleScript.path, contents: Data())
        FileManager.default.createFile(atPath: unrelated.path, contents: Data())

        SSHAgentService.removeStaleAskPassScripts(directory: temporaryDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleScript.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testStaleAgentSocketsAreRemoved() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let staleSocket = temporaryDirectory.appendingPathComponent("agent-123.sock")
        let unrelated = temporaryDirectory.appendingPathComponent("agent.env")
        FileManager.default.createFile(atPath: staleSocket.path, contents: Data())
        FileManager.default.createFile(atPath: unrelated.path, contents: Data())

        SSHAgentService.removeStaleAgentSockets(directory: temporaryDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleSocket.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testConnectionStoreWritesOwnerOnlyProfileFile() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = temporaryDirectory.appendingPathComponent("connections.json")
        let store = ConnectionStore(storageURL: storageURL)

        store.upsert(ConnectionProfile(name: "Prod", host: "example.com", username: "deploy"))

        let attributes = try FileManager.default.attributesOfItem(atPath: storageURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testConnectionStoreDeletePersistsAcrossReload() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = temporaryDirectory.appendingPathComponent("connections.json")
        let keychain = SpyKeychainStore()
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy")

        let store = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertTrue(store.upsert(profile))

        XCTAssertTrue(store.delete(profile))

        let reloadedStore = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertEqual(reloadedStore.profiles, [])
        let storedData = try Data(contentsOf: storageURL)
        let storedProfiles = try JSONDecoder().decode([ConnectionProfile].self, from: storedData)
        XCTAssertEqual(storedProfiles, [])
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testConnectionStoreAddSavesKeychainSecretWithProfile() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = temporaryDirectory.appendingPathComponent("connections.json")
        let keychain = SpyKeychainStore()
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy", storesKeyPassphrase: true)
        let store = ConnectionStore(storageURL: storageURL, keychain: keychain)

        XCTAssertTrue(store.upsert(profile, keychainUpdate: .saveSecret("secret")))

        XCTAssertEqual(store.profiles, [profile])
        XCTAssertEqual(keychain.secrets[profile.id.uuidString], "secret")
        let reloadedStore = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertEqual(reloadedStore.profiles, [profile])
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testConnectionStoreRollsBackNewKeychainSecretWhenAddPersistenceFails() throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let keychain = SpyKeychainStore()
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy", storesKeyPassphrase: true)
        let store = ConnectionStore(storageURL: storageURL, keychain: keychain)

        XCTAssertFalse(store.upsert(profile, keychainUpdate: .saveSecret("secret")))

        XCTAssertEqual(store.profiles, [])
        XCTAssertNil(keychain.secrets[profile.id.uuidString])
        try FileManager.default.removeItem(at: storageURL)
    }

    func testConnectionStoreDeleteRemovesKeychainSecretWithProfile() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = temporaryDirectory.appendingPathComponent("connections.json")
        let keychain = SpyKeychainStore()
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy", storesKeyPassphrase: true)
        keychain.secrets[profile.id.uuidString] = "secret"
        let store = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertTrue(store.upsert(profile))

        XCTAssertTrue(store.delete(profile))

        XCTAssertEqual(store.profiles, [])
        XCTAssertNil(keychain.secrets[profile.id.uuidString])
        let reloadedStore = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertEqual(reloadedStore.profiles, [])
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testConnectionStoreDoesNotDeleteProfileWhenKeychainDeleteFails() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = temporaryDirectory.appendingPathComponent("connections.json")
        let keychain = SpyKeychainStore()
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy", storesKeyPassphrase: true)
        keychain.secrets[profile.id.uuidString] = "secret"
        let store = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertTrue(store.upsert(profile))
        keychain.deleteError = KeychainError(status: errSecInteractionNotAllowed)

        XCTAssertFalse(store.delete(profile))

        XCTAssertEqual(store.profiles, [profile])
        XCTAssertEqual(keychain.secrets[profile.id.uuidString], "secret")
        let reloadedStore = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertEqual(reloadedStore.profiles, [profile])
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testConnectionStoreDoesNotVisuallyDeleteWhenPersistenceFails() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = temporaryDirectory.appendingPathComponent("connections.json")
        let keychain = SpyKeychainStore()
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy")
        let store = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertTrue(store.upsert(profile))

        try FileManager.default.removeItem(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

        XCTAssertFalse(store.delete(profile))

        XCTAssertEqual(store.profiles, [profile])
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testConnectionStoreDoesNotCommitInMemoryProfilesWhenPersistenceFails() throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let store = ConnectionStore(storageURL: storageURL)

        let didSave = store.upsert(ConnectionProfile(name: "Prod", host: "example.com", username: "deploy"))

        XCTAssertFalse(didSave)
        XCTAssertEqual(store.profiles, [])
        try FileManager.default.removeItem(at: storageURL)
    }

    func testConnectionStoreSecuresExistingStorageDirectory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        _ = ConnectionStore(storageURL: temporaryDirectory.appendingPathComponent("connections.json"))

        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryDirectory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testProcessExitRemovesSelectedSessionAndSelectsPreviousTab() {
        let store = TerminalSessionStore()
        store.openLocal()
        let first = store.sessions[0]
        store.openLocal()
        let second = store.sessions[1]

        store.handleProcessExit(second, exitCode: 0)

        XCTAssertEqual(store.sessions.map(\.id), [first.id])
        XCTAssertEqual(store.selectedSessionID, first.id)
    }

    func testProcessExitRemovesUnselectedSessionWithoutChangingSelection() {
        let store = TerminalSessionStore()
        store.openLocal()
        let first = store.sessions[0]
        store.openLocal()
        let second = store.sessions[1]

        store.handleProcessExit(first, exitCode: 0)

        XCTAssertEqual(store.sessions.map(\.id), [second.id])
        XCTAssertEqual(store.selectedSessionID, second.id)
    }

    func testProcessExitOfLastSessionStartsReplacementLocalSession() {
        let store = TerminalSessionStore()
        store.openLocal()
        let original = store.sessions[0]

        store.handleProcessExit(original, exitCode: 0)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertNotEqual(store.sessions[0].id, original.id)
        XCTAssertEqual(store.sessions[0].launch.executable, TerminalLaunch.localShell().executable)
        XCTAssertEqual(store.selectedSessionID, store.sessions[0].id)
    }

    func testClosingLastSessionStartsReplacementLocalSession() {
        let store = TerminalSessionStore()
        store.openLocal()
        let original = store.sessions[0]

        store.close(original)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertNotEqual(store.sessions[0].id, original.id)
        XCTAssertEqual(store.sessions[0].launch.executable, TerminalLaunch.localShell().executable)
        XCTAssertEqual(store.selectedSessionID, store.sessions[0].id)
    }

    func testCloseSelectedSessionClosesActiveTab() {
        let store = TerminalSessionStore()
        store.openLocal()
        let first = store.sessions[0]
        store.openLocal()
        let second = store.sessions[1]

        XCTAssertTrue(store.closeSelectedSession())

        XCTAssertEqual(store.sessions.map(\.id), [first.id])
        XCTAssertEqual(store.selectedSessionID, first.id)
        XCTAssertTrue(second.isClosed)
    }

    func testCloseSelectedSessionKeepsReplacementWhenLastTabCloses() {
        let store = TerminalSessionStore()
        store.openLocal()
        let original = store.sessions[0]

        XCTAssertTrue(store.closeSelectedSession())

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertNotEqual(store.sessions[0].id, original.id)
        XCTAssertEqual(store.selectedSessionID, store.sessions[0].id)
        XCTAssertTrue(original.isClosed)
    }

    func testMainWindowCloseRequestsApplicationTerminationInsteadOfClosingTab() {
        XCTAssertEqual(
            MainWindowCloseBehavior.decision(isMainWindow: true, isQuitting: false),
            .requestApplicationTermination
        )
        XCTAssertEqual(
            MainWindowCloseBehavior.decision(isMainWindow: true, isQuitting: true),
            .allowWindowClose
        )
        XCTAssertEqual(
            MainWindowCloseBehavior.decision(isMainWindow: false, isQuitting: false),
            .allowWindowClose
        )
    }

    func testRemoteNonzeroProcessExitKeepsSessionVisibleForDiagnostics() {
        let store = TerminalSessionStore()
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy")
        store.openSSH(profile: profile)
        let session = store.sessions[0]

        store.handleProcessExit(session, exitCode: 255)

        XCTAssertEqual(store.sessions.map(\.id), [session.id])
        XCTAssertEqual(store.selectedSessionID, session.id)
        XCTAssertFalse(session.isClosed)
    }
}

private final class SpySSHAgentService: SSHAgentManaging {
    var preparation: SSHAgentPreparation
    private(set) var removedProfileIDs: [UUID] = []
    private(set) var shutdownCallCount = 0

    init(preparation: SSHAgentPreparation = SSHAgentPreparation()) {
        self.preparation = preparation
    }

    func prepareIdentityIfNeeded(for profile: ConnectionProfile) -> SSHAgentPreparation {
        preparation
    }

    func removeIdentity(for profile: ConnectionProfile) {
        removedProfileIDs.append(profile.id)
    }

    func shutdown() {
        shutdownCallCount += 1
    }
}

private final class SpyKeychainStore: KeychainManaging {
    var secrets: [String: String] = [:]
    var saveError: Error?
    var readError: Error?
    var deleteError: Error?
    var onRead: (() -> Void)?

    func saveSecret(_ secret: String, account: String) throws {
        if let saveError {
            throw saveError
        }
        secrets[account] = secret
    }

    func readSecret(account: String) throws -> String? {
        onRead?()
        if let readError {
            throw readError
        }
        return secrets[account]
    }

    func hasSecret(account: String) -> Bool {
        secrets[account] != nil
    }

    func deleteSecret(account: String) throws {
        if let deleteError {
            throw deleteError
        }
        secrets[account] = nil
    }
}
