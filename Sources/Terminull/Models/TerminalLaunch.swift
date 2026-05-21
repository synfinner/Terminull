import Foundation

struct TerminalLaunch: Equatable {
    var executable: String
    var args: [String]
    var environment: [String]?
    var execName: String?
    var currentDirectory: String?
    var startupMessage: String?

    static func localShell() -> TerminalLaunch {
        let shell = ShellResolver.defaultShell()
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        return TerminalLaunch(
            executable: shell,
            args: [],
            environment: nil,
            execName: "-\(shellName)",
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            startupMessage: nil
        )
    }

    static func ssh(profile: ConnectionProfile, environment: [String]? = nil) -> TerminalLaunch {
        var args: [String] = [
            "-tt",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "AddKeysToAgent=no",
            "-o", "UseKeychain=no",
            "-p", String(profile.port)
        ]

        let keyPath = profile.identityFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyPath.isEmpty {
            args.append(contentsOf: ["-i", keyPath, "-o", "IdentitiesOnly=yes"])
        }

        args.append("--")
        args.append(profile.target)

        return TerminalLaunch(
            executable: "/usr/bin/ssh",
            args: args,
            environment: environment,
            execName: nil,
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            startupMessage: "Connecting to \(profile.target):\(profile.port)...\r\n"
        )
    }
}
