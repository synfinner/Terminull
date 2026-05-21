import Foundation
import Darwin

enum ShellResolver {
    static func defaultShell() -> String {
        defaultShell(loginShell: systemLoginShell(), allowedShells: allowedLoginShells())
    }

    static func defaultShell(loginShell: String?, allowedShells: Set<String>) -> String {
        if let shell = loginShell, isAllowedLoginShell(shell, allowedShells: allowedShells) {
            return shell
        }

        if isAllowedLoginShell("/bin/zsh", allowedShells: allowedShells) {
            return "/bin/zsh"
        }

        if FileManager.default.isExecutableFile(atPath: "/bin/bash") {
            return "/bin/bash"
        }

        return "/bin/sh"
    }

    private static func systemLoginShell() -> String? {
        guard let passwd = getpwuid(getuid()), let shell = passwd.pointee.pw_shell else {
            return nil
        }
        return String(cString: shell)
    }

    private static func allowedLoginShells() -> Set<String> {
        guard let contents = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) else {
            return ["/bin/zsh", "/bin/bash", "/bin/sh"]
        }

        let shells = contents
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        return Set(shells)
    }

    private static func isAllowedLoginShell(_ shell: String, allowedShells: Set<String>) -> Bool {
        guard shell.hasPrefix("/"), allowedShells.contains(shell), FileManager.default.isExecutableFile(atPath: shell) else {
            return false
        }

        return true
    }
}
