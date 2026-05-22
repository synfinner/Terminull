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
        XCTAssertEqual(TerminullReleaseMetadata.version, "0.1.4")
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

    func testConnectionProfileDecodesMissingLoginPasswordStorageFlag() throws {
        let data = """
        {
          "id": "04BED745-3DC2-4BB8-926D-3A5BF09A56D0",
          "name": "Prod",
          "host": "example.com",
          "username": "deploy",
          "port": 22,
          "identityFilePath": "",
          "storesKeyPassphrase": false
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(ConnectionProfile.self, from: data)

        XCTAssertFalse(profile.storesLoginPassword)
    }

    func testConnectionProfileDecodesLegacyProfileWithoutKeyOrPortFields() throws {
        let id = UUID()
        let data = """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy",
          "host": "example.com",
          "username": "deploy"
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(ConnectionProfile.self, from: data)

        XCTAssertEqual(profile.id, id)
        XCTAssertEqual(profile.port, 22)
        XCTAssertEqual(profile.identityFilePath, "")
        XCTAssertFalse(profile.storesKeyPassphrase)
        XCTAssertFalse(profile.storesLoginPassword)
    }

    func testConnectionProfileNormalizesInvalidPort() {
        XCTAssertEqual(ConnectionProfile(name: "Prod", host: "example.com", username: "deploy", port: 0).port, 22)
        XCTAssertEqual(ConnectionProfile(name: "Prod", host: "example.com", username: "deploy", port: 65536).port, 22)
        XCTAssertEqual(ConnectionProfile(name: "Prod", host: "example.com", username: "deploy", port: 2222).port, 2222)
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

    func testSSHLaunchLimitsPromptsWhenSavedLoginPasswordIsConfigured() {
        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            storesLoginPassword: true
        )

        let launch = TerminalLaunch.ssh(profile: profile)

        XCTAssertTrue(launch.args.contains("NumberOfPasswordPrompts=1"))
        XCTAssertTrue(launch.args.contains("PasswordAuthentication=yes"))
        XCTAssertTrue(launch.args.contains("KbdInteractiveAuthentication=no"))
        XCTAssertTrue(launch.args.contains("PreferredAuthentications=password"))
        XCTAssertTrue(launch.args.contains("PubkeyAuthentication=no"))
    }

    func testSSHLaunchAllowsPublicKeyBeforeSavedLoginPasswordWhenKeyIsConfigured() {
        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            identityFilePath: "/Users/test/.ssh/id_ed25519",
            storesLoginPassword: true
        )

        let launch = TerminalLaunch.ssh(profile: profile)

        XCTAssertTrue(launch.args.contains("PreferredAuthentications=publickey,password"))
        XCTAssertFalse(launch.args.contains("PubkeyAuthentication=no"))
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

    func testSSHAgentProcessRunnerPassesStandardInputToLaunchedProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")

        let result = try SSHAgentService.run(
            process: process,
            timeout: 2,
            label: "cat",
            standardInput: Data("hello\n".utf8)
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.stdout, "hello\n")
        XCTAssertEqual(result.stderr, "")
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

        let environment = store.sessions.first?.launch.environment ?? []
        XCTAssertTrue(environment.contains("SSH_AUTH_SOCK=/tmp/terminull-agent.sock"))
        XCTAssertTrue(environment.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
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

    func testConnectionEditorPromptsToSavePassphraseWhenKeyIsChosen() {
        XCTAssertTrue(
            ConnectionEditorPassphrasePrompt.shouldPromptBeforeSaving(
                keyPath: "/Users/synfinner/.ssh/id_ed25519",
                rememberPassphrase: false,
                existingStoresKeyPassphrase: false,
                skippedPrompt: false
            )
        )
        XCTAssertFalse(
            ConnectionEditorPassphrasePrompt.shouldPromptBeforeSaving(
                keyPath: "",
                rememberPassphrase: false,
                existingStoresKeyPassphrase: false,
                skippedPrompt: false
            )
        )
        XCTAssertFalse(
            ConnectionEditorPassphrasePrompt.shouldPromptBeforeSaving(
                keyPath: "/Users/synfinner/.ssh/id_ed25519",
                rememberPassphrase: true,
                existingStoresKeyPassphrase: false,
                skippedPrompt: false
            )
        )
        XCTAssertFalse(
            ConnectionEditorPassphrasePrompt.shouldPromptBeforeSaving(
                keyPath: "/Users/synfinner/.ssh/id_ed25519",
                rememberPassphrase: false,
                existingStoresKeyPassphrase: false,
                skippedPrompt: true
            )
        )
    }

    func testConnectionEditorRejectsInvalidPorts() {
        XCTAssertFalse(ConnectionEditorPortValidator.isValid(0))
        XCTAssertTrue(ConnectionEditorPortValidator.isValid(1))
        XCTAssertTrue(ConnectionEditorPortValidator.isValid(22))
        XCTAssertTrue(ConnectionEditorPortValidator.isValid(65535))
        XCTAssertFalse(ConnectionEditorPortValidator.isValid(65536))
    }

    func testConnectionEditorExistingPassphraseOnlyAppliesToSameKeyPath() {
        XCTAssertTrue(
            ConnectionEditorPassphraseState.existingPassphraseStillApplies(
                existingStoresKeyPassphrase: true,
                existingKeyPath: " /Users/test/.ssh/id_ed25519 ",
                newKeyPath: "/Users/test/.ssh/id_ed25519"
            )
        )
        XCTAssertFalse(
            ConnectionEditorPassphraseState.existingPassphraseStillApplies(
                existingStoresKeyPassphrase: true,
                existingKeyPath: "/Users/test/.ssh/id_ed25519",
                newKeyPath: "/Users/test/.ssh/id_rsa"
            )
        )
        XCTAssertFalse(
            ConnectionEditorPassphraseState.existingPassphraseStillApplies(
                existingStoresKeyPassphrase: false,
                existingKeyPath: "/Users/test/.ssh/id_ed25519",
                newKeyPath: "/Users/test/.ssh/id_ed25519"
            )
        )
    }

    func testSSHLoginPasswordAskPassEnvironmentUsesMainExecutableAndOneUseToken() {
        let environment = SSHLoginPasswordAskPass.environment(
            account: "profile-id:login-password",
            tokenAccount: "profile-id:login-password-token:session-id",
            token: "one-use-token",
            executablePath: "/Applications/Terminull.app/Contents/MacOS/Terminull"
        )

        XCTAssertTrue(environment.contains("SSH_ASKPASS=/Applications/Terminull.app/Contents/MacOS/Terminull"))
        XCTAssertTrue(environment.contains("SSH_ASKPASS_REQUIRE=force"))
        XCTAssertTrue(environment.contains("TERMINULL_ASKPASS_MODE=1"))
        XCTAssertTrue(environment.contains("TERMINULL_ASKPASS_ACCOUNT=profile-id:login-password"))
        XCTAssertTrue(environment.contains("TERMINULL_ASKPASS_TOKEN_ACCOUNT=profile-id:login-password-token:session-id"))
        XCTAssertTrue(environment.contains("TERMINULL_ASKPASS_TOKEN=one-use-token"))
        XCTAssertFalse(environment.contains { $0.hasPrefix("DISPLAY=") })
    }

    func testSSHLoginPasswordAskPassCommandPrintsPasswordAndConsumesToken() throws {
        let keychain = SpyKeychainStore()
        let account = "profile-id:login-password"
        let tokenAccount = "profile-id:login-password-token:session-id"
        keychain.secrets[account] = "login-secret"
        keychain.secrets[tokenAccount] = "one-use-token"
        let pipe = Pipe()

        let exitCode = SSHLoginPasswordAskPassCommand.runIfRequested(
            environment: [
                SSHLoginPasswordAskPass.modeVariable: "1",
                SSHLoginPasswordAskPass.accountVariable: account,
                SSHLoginPasswordAskPass.tokenAccountVariable: tokenAccount,
                SSHLoginPasswordAskPass.tokenVariable: "one-use-token"
            ],
            arguments: ["Terminull", "deploy@example.com's password:"],
            keychain: keychain,
            output: pipe.fileHandleForWriting
        )
        try pipe.fileHandleForWriting.close()

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "login-secret\n")
        XCTAssertNil(keychain.secrets[tokenAccount])
    }

    func testSSHLoginPasswordAskPassCommandRejectsNonPasswordPromptsWithoutConsumingToken() throws {
        let keychain = SpyKeychainStore()
        let account = "profile-id:login-password"
        let tokenAccount = "profile-id:login-password-token:session-id"
        keychain.secrets[account] = "login-secret"
        keychain.secrets[tokenAccount] = "one-use-token"
        let pipe = Pipe()

        let exitCode = SSHLoginPasswordAskPassCommand.runIfRequested(
            environment: [
                SSHLoginPasswordAskPass.modeVariable: "1",
                SSHLoginPasswordAskPass.accountVariable: account,
                SSHLoginPasswordAskPass.tokenAccountVariable: tokenAccount,
                SSHLoginPasswordAskPass.tokenVariable: "one-use-token"
            ],
            arguments: ["Terminull", "Enter passphrase for key '/Users/test/.ssh/id_ed25519':"],
            keychain: keychain,
            output: pipe.fileHandleForWriting
        )
        try pipe.fileHandleForWriting.close()

        XCTAssertEqual(exitCode, 1)
        XCTAssertEqual(pipe.fileHandleForReading.readDataToEndOfFile(), Data())
        XCTAssertEqual(keychain.secrets[tokenAccount], "one-use-token")
    }

    func testConnectionEditorLoginPasswordDecisionCanSaveKeepAndRemove() {
        let save = ConnectionEditorLoginPasswordDecision.resolve(
            enteredPassword: "secret",
            existingStoresLoginPassword: false,
            removeSavedPassword: false
        )
        XCTAssertTrue(save.storesLoginPassword)
        XCTAssertEqual(save.keychainUpdate, .saveSecret("secret"))

        let keep = ConnectionEditorLoginPasswordDecision.resolve(
            enteredPassword: "",
            existingStoresLoginPassword: true,
            removeSavedPassword: false
        )
        XCTAssertTrue(keep.storesLoginPassword)
        XCTAssertEqual(keep.keychainUpdate, .unchanged)

        let remove = ConnectionEditorLoginPasswordDecision.resolve(
            enteredPassword: "",
            existingStoresLoginPassword: true,
            removeSavedPassword: true
        )
        XCTAssertFalse(remove.storesLoginPassword)
        XCTAssertEqual(remove.keychainUpdate, .deleteSecret)
    }

    func testKeychainServiceFallsBackWhenDataProtectionEntitlementIsUnavailable() {
        XCTAssertTrue(KeychainService.shouldFallBackToLoginKeychain(status: errSecMissingEntitlement))
        XCTAssertFalse(KeychainService.shouldFallBackToLoginKeychain(status: errSecAuthFailed))
    }

    func testKeychainServiceSavesReadsAndDeletesInCurrentSigningContext() throws {
        let account = "terminull-test-\(UUID().uuidString)"
        let keychain = KeychainService()

        try keychain.deleteSecret(account: account)
        defer {
            try? keychain.deleteSecret(account: account)
        }

        try keychain.saveSecret("temporary-secret", account: account)
        XCTAssertEqual(try keychain.readSecret(account: account), "temporary-secret")
        XCTAssertTrue(keychain.hasSecret(account: account))

        try keychain.deleteSecret(account: account)
        XCTAssertNil(try keychain.readSecret(account: account))
        XCTAssertFalse(keychain.hasSecret(account: account))
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

    func testConnectionStoreAddSavesLoginPasswordWithProfile() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = temporaryDirectory.appendingPathComponent("connections.json")
        let keychain = SpyKeychainStore()
        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            storesLoginPassword: true
        )
        let store = ConnectionStore(storageURL: storageURL, keychain: keychain)

        XCTAssertTrue(
            store.upsert(
                profile,
                keychainUpdates: [
                    .init(account: ConnectionSecretAccount.loginPassword(for: profile.id), update: .saveSecret("login-secret"))
                ]
            )
        )

        XCTAssertEqual(store.profiles, [profile])
        XCTAssertEqual(keychain.secrets[ConnectionSecretAccount.loginPassword(for: profile.id)], "login-secret")
        let storedData = try Data(contentsOf: storageURL)
        XCTAssertFalse(String(data: storedData, encoding: .utf8)?.contains("login-secret") ?? true)
        let reloadedStore = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertEqual(reloadedStore.profiles, [profile])
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testConnectionStoreDoesNotAddProfileWhenLoginPasswordSaveFails() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = temporaryDirectory.appendingPathComponent("connections.json")
        let keychain = SpyKeychainStore()
        keychain.saveError = KeychainError(status: errSecInteractionNotAllowed)
        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            storesLoginPassword: true
        )
        let store = ConnectionStore(storageURL: storageURL, keychain: keychain)

        XCTAssertFalse(
            store.upsert(
                profile,
                keychainUpdates: [
                    .init(account: ConnectionSecretAccount.loginPassword(for: profile.id), update: .saveSecret("login-secret"))
                ]
            )
        )

        XCTAssertEqual(store.profiles, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testConnectionStoreReloadsProfilesAfterMarkConnectedWritesDate() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = temporaryDirectory.appendingPathComponent("connections.json")
        let profile = ConnectionProfile(name: "Prod", host: "example.com", username: "deploy")
        let store = ConnectionStore(storageURL: storageURL)
        XCTAssertTrue(store.upsert(profile))

        store.markConnected(profile)

        let reloadedStore = ConnectionStore(storageURL: storageURL)
        XCTAssertEqual(reloadedStore.profiles.count, 1)
        let reloadedProfile = try XCTUnwrap(reloadedStore.profiles.first)
        XCTAssertEqual(reloadedProfile.id, profile.id)
        XCTAssertNotNil(reloadedProfile.lastConnectedAt)
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
        keychain.secrets[ConnectionSecretAccount.loginPassword(for: profile.id)] = "login-secret"
        let store = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertTrue(store.upsert(profile))

        XCTAssertTrue(store.delete(profile))

        XCTAssertEqual(store.profiles, [])
        XCTAssertNil(keychain.secrets[profile.id.uuidString])
        XCTAssertNil(keychain.secrets[ConnectionSecretAccount.loginPassword(for: profile.id)])
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

    func testConnectionStoreDoesNotDeleteProfileWhenLoginPasswordDeleteFails() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = temporaryDirectory.appendingPathComponent("connections.json")
        let keychain = SpyKeychainStore()
        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            storesLoginPassword: true
        )
        keychain.secrets[ConnectionSecretAccount.loginPassword(for: profile.id)] = "login-secret"
        let store = ConnectionStore(storageURL: storageURL, keychain: keychain)
        XCTAssertTrue(store.upsert(profile))
        keychain.deleteError = KeychainError(status: errSecInteractionNotAllowed)

        XCTAssertFalse(store.delete(profile))

        XCTAssertEqual(store.profiles, [profile])
        XCTAssertEqual(keychain.secrets[ConnectionSecretAccount.loginPassword(for: profile.id)], "login-secret")
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

    func testTerminalSessionStoreUsesAskPassForSavedLoginPassword() {
        let keychain = SpyKeychainStore()
        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            storesLoginPassword: true
        )
        keychain.secrets[ConnectionSecretAccount.loginPassword(for: profile.id)] = "login-secret"
        let store = TerminalSessionStore(
            sshAgentService: SpySSHAgentService(),
            keychain: keychain,
            askPassExecutablePath: { "/bin/echo" }
        )

        store.openSSH(profile: profile)

        let environment = store.sessions.first?.launch.environment ?? []
        XCTAssertTrue(environment.contains("SSH_ASKPASS=/bin/echo"))
        XCTAssertTrue(environment.contains("SSH_ASKPASS_REQUIRE=force"))
        XCTAssertTrue(environment.contains("TERMINULL_ASKPASS_MODE=1"))
        XCTAssertTrue(environment.contains("TERMINULL_ASKPASS_ACCOUNT=\(ConnectionSecretAccount.loginPassword(for: profile.id))"))
        XCTAssertTrue(environment.contains { $0.hasPrefix("TERMINULL_ASKPASS_TOKEN_ACCOUNT=\(profile.id.uuidString):login-password-token:") })
        XCTAssertTrue(environment.contains { $0.hasPrefix("TERMINULL_ASKPASS_TOKEN=") })
        XCTAssertTrue(environment.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
        XCTAssertFalse(environment.contains { $0.contains("login-secret") })
        XCTAssertTrue(keychain.secrets.keys.contains { $0.hasPrefix("\(profile.id.uuidString):login-password-token:") })
    }

    func testTerminalSessionStoreWarnsWhenSavedLoginPasswordIsMissing() {
        let keychain = SpyKeychainStore()
        let profile = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            username: "deploy",
            storesLoginPassword: true
        )
        let store = TerminalSessionStore(
            sshAgentService: SpySSHAgentService(),
            keychain: keychain,
            askPassExecutablePath: { "/Applications/Terminull.app/Contents/MacOS/Terminull" }
        )

        store.openSSH(profile: profile)

        XCTAssertTrue(store.sessions.first?.warning?.contains("Saved SSH login password was not found in Keychain") == true)
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
