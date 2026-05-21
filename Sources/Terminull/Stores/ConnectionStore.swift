import Foundation

enum ConnectionKeychainUpdate: Equatable {
    case unchanged
    case saveSecret(String)
    case deleteSecret

    var changesKeychain: Bool {
        switch self {
        case .unchanged:
            return false
        case .saveSecret, .deleteSecret:
            return true
        }
    }
}

struct ConnectionKeychainMutation {
    let account: String
    let update: ConnectionKeychainUpdate
}

enum ConnectionSecretAccount {
    static func keyPassphrase(for profileID: UUID) -> String {
        profileID.uuidString
    }

    static func loginPassword(for profileID: UUID) -> String {
        "\(profileID.uuidString):login-password"
    }

    static func loginPasswordAskPassToken(for profileID: UUID, sessionID: UUID) -> String {
        "\(profileID.uuidString):login-password-token:\(sessionID.uuidString)"
    }
}

final class ConnectionStore: ObservableObject {
    @Published private(set) var profiles: [ConnectionProfile] = []

    private let storageURL: URL
    private let keychain: any KeychainManaging

    init(
        storageURL: URL = SupportPaths.applicationSupportDirectory.appendingPathComponent("connections.json"),
        keychain: any KeychainManaging = KeychainService()
    ) {
        self.storageURL = storageURL
        self.keychain = keychain
        secureStorageLocation()
        load()
    }

    @discardableResult
    func upsert(
        _ profile: ConnectionProfile,
        keychainUpdate: ConnectionKeychainUpdate = .unchanged
    ) -> Bool {
        upsert(
            profile,
            keychainUpdates: [
                ConnectionKeychainMutation(
                    account: ConnectionSecretAccount.keyPassphrase(for: profile.id),
                    update: keychainUpdate
                )
            ]
        )
    }

    @discardableResult
    func upsert(
        _ profile: ConnectionProfile,
        keychainUpdates: [ConnectionKeychainMutation]
    ) -> Bool {
        var updatedProfiles = profiles
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            updatedProfiles[index] = profile
        } else {
            updatedProfiles.append(profile)
        }
        updatedProfiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        return persist(
            updatedProfiles,
            keychainUpdates: keychainUpdates
        )
    }

    func markConnected(_ profile: ConnectionProfile) {
        var updated = profile
        updated.lastConnectedAt = Date()
        upsert(updated)
    }

    @discardableResult
    func delete(_ profile: ConnectionProfile) -> Bool {
        let updatedProfiles = profiles.filter { $0.id != profile.id }
        return persist(
            updatedProfiles,
            keychainUpdates: [
                ConnectionKeychainMutation(
                    account: ConnectionSecretAccount.keyPassphrase(for: profile.id),
                    update: .deleteSecret
                ),
                ConnectionKeychainMutation(
                    account: ConnectionSecretAccount.loginPassword(for: profile.id),
                    update: .deleteSecret
                )
            ]
        )
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            profiles = []
            return
        }
        profiles = (try? JSONDecoder.connectionProfiles.decode([ConnectionProfile].self, from: data)) ?? []
    }

    private func save(_ profiles: [ConnectionProfile]) -> Bool {
        do {
            let data = try JSONEncoder.pretty.encode(profiles)
            try data.write(to: storageURL, options: [.atomic])
            try FileManager.default.applyOwnerOnlyFilePermissions(at: storageURL)
            return true
        } catch {
            NSLog("Terminull failed to save connections: \(error.localizedDescription)")
            return false
        }
    }

    private func persist(
        _ updatedProfiles: [ConnectionProfile],
        keychainUpdates: [ConnectionKeychainMutation]
    ) -> Bool {
        let mutations = keychainUpdates.filter(\.update.changesKeychain)
        var previousSecrets: [ConnectionKeychainSnapshot] = []
        var appliedSnapshots: [ConnectionKeychainSnapshot] = []
        do {
            for mutation in mutations {
                previousSecrets.append(ConnectionKeychainSnapshot(
                    account: mutation.account,
                    secret: try keychain.readSecret(account: mutation.account)
                ))
            }
            for (mutation, snapshot) in zip(mutations, previousSecrets) {
                try apply(mutation.update, account: mutation.account)
                appliedSnapshots.append(snapshot)
            }
        } catch {
            restoreKeychainSecrets(appliedSnapshots)
            NSLog("Terminull failed to update Keychain for connection: \(error.localizedDescription)")
            return false
        }

        guard save(updatedProfiles) else {
            restoreKeychainSecrets(previousSecrets)
            return false
        }

        profiles = updatedProfiles
        return true
    }

    private func apply(_ update: ConnectionKeychainUpdate, account: String) throws {
        switch update {
        case .unchanged:
            return
        case .saveSecret(let secret):
            try keychain.saveSecret(secret, account: account)
        case .deleteSecret:
            try keychain.deleteSecret(account: account)
        }
    }

    private func restoreKeychainSecrets(_ snapshots: [ConnectionKeychainSnapshot]) {
        for snapshot in snapshots {
            do {
                if let secret = snapshot.secret {
                    try keychain.saveSecret(secret, account: snapshot.account)
                } else {
                    try keychain.deleteSecret(account: snapshot.account)
                }
            } catch {
                NSLog("Terminull failed to restore Keychain state after connection save failure: \(error.localizedDescription)")
            }
        }
    }

    private func secureStorageLocation() {
        do {
            try FileManager.default.createPrivateDirectory(at: storageURL.deletingLastPathComponent())
            if FileManager.default.fileExists(atPath: storageURL.path) {
                try FileManager.default.applyOwnerOnlyFilePermissions(at: storageURL)
            }
        } catch {
            NSLog("Terminull failed to secure connection storage: \(error.localizedDescription)")
        }
    }
}

private struct ConnectionKeychainSnapshot {
    let account: String
    let secret: String?
}

private extension JSONDecoder {
    static var connectionProfiles: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
