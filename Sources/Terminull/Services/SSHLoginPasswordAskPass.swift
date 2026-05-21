import Foundation
import Security

enum SSHLoginPasswordAskPass {
    static let modeVariable = "TERMINULL_ASKPASS_MODE"
    static let accountVariable = "TERMINULL_ASKPASS_ACCOUNT"
    static let tokenAccountVariable = "TERMINULL_ASKPASS_TOKEN_ACCOUNT"
    static let tokenVariable = "TERMINULL_ASKPASS_TOKEN"

    static func executablePath(bundle: Bundle = .main) -> String? {
        bundle.executableURL?.path
    }

    static func makeToken(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        return Data(bytes).base64EncodedString()
    }

    static func environment(
        account: String,
        tokenAccount: String,
        token: String,
        executablePath: String
    ) -> [String] {
        [
            "DISPLAY=terminull",
            "SSH_ASKPASS=\(executablePath)",
            "SSH_ASKPASS_REQUIRE=force",
            "\(modeVariable)=1",
            "\(accountVariable)=\(account)",
            "\(tokenAccountVariable)=\(tokenAccount)",
            "\(tokenVariable)=\(token)"
        ]
    }

    static func isPasswordPrompt(_ prompt: String?) -> Bool {
        guard let prompt else {
            return false
        }
        let lowercased = prompt.lowercased()
        return lowercased.contains("password")
            && !lowercased.contains("passphrase")
            && !lowercased.contains("verification")
            && !lowercased.contains("token")
    }
}

enum SSHLoginPasswordAskPassCommand {
    static func runIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        keychain: any KeychainManaging = KeychainService(),
        output: FileHandle = .standardOutput
    ) -> Int32? {
        guard environment[SSHLoginPasswordAskPass.modeVariable] == "1" else {
            return nil
        }

        guard SSHLoginPasswordAskPass.isPasswordPrompt(arguments.dropFirst().first),
              let account = environment[SSHLoginPasswordAskPass.accountVariable],
              let tokenAccount = environment[SSHLoginPasswordAskPass.tokenAccountVariable],
              let presentedToken = environment[SSHLoginPasswordAskPass.tokenVariable],
              !account.isEmpty,
              !tokenAccount.isEmpty,
              !presentedToken.isEmpty else {
            return 1
        }

        do {
            guard let storedToken = try keychain.readSecret(account: tokenAccount),
                  constantTimeEquals(storedToken, presentedToken) else {
                return 1
            }

            try keychain.deleteSecret(account: tokenAccount)

            guard let password = try keychain.readSecret(account: account), !password.isEmpty else {
                return 1
            }

            output.write(Data("\(password)\n".utf8))
            return 0
        } catch {
            return 1
        }
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        let count = max(left.count, right.count)
        var difference = left.count ^ right.count

        for index in 0..<count {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= Int(leftByte ^ rightByte)
        }

        return difference == 0
    }
}
