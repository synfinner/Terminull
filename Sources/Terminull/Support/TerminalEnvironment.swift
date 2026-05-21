import Foundation

enum TerminalEnvironment {
    static func variables(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        extra: [String: String] = [:]
    ) -> [String] {
        processEnvironment(baseEnvironment: baseEnvironment, extra: extra)
            .map { "\($0.key)=\($0.value)" }
            .sorted()
    }

    static func processEnvironment(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        extra: [String: String] = [:]
    ) -> [String: String] {
        var environment: [String: String] = [
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "LANG": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        for key in ["HOME", "USER", "LOGNAME", "DISPLAY", "LC_CTYPE", "TMPDIR"] {
            if let value = baseEnvironment[key], !value.isEmpty {
                environment[key] = value
            }
        }

        for (key, value) in extra {
            environment[key] = value
        }

        return environment
    }
}
