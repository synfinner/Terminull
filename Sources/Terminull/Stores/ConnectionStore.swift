import Foundation

enum ConnectionKeychainUpdate {
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
        var updatedProfiles = profiles
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            updatedProfiles[index] = profile
        } else {
            updatedProfiles.append(profile)
        }
        updatedProfiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        return persist(
            updatedProfiles,
            keychainUpdate: keychainUpdate,
            account: profile.id.uuidString
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
            keychainUpdate: .deleteSecret,
            account: profile.id.uuidString
        )
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            profiles = []
            return
        }
        profiles = (try? JSONDecoder().decode([ConnectionProfile].self, from: data)) ?? []
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
        keychainUpdate: ConnectionKeychainUpdate,
        account: String
    ) -> Bool {
        let previousSecret: String?
        if keychainUpdate.changesKeychain {
            do {
                previousSecret = try keychain.readSecret(account: account)
                try apply(keychainUpdate, account: account)
            } catch {
                NSLog("Terminull failed to update Keychain for connection: \(error.localizedDescription)")
                return false
            }
        } else {
            previousSecret = nil
        }

        guard save(updatedProfiles) else {
            if keychainUpdate.changesKeychain {
                restoreKeychainSecret(previousSecret, account: account)
            }
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

    private func restoreKeychainSecret(_ secret: String?, account: String) {
        do {
            if let secret {
                try keychain.saveSecret(secret, account: account)
            } else {
                try keychain.deleteSecret(account: account)
            }
        } catch {
            NSLog("Terminull failed to restore Keychain state after connection save failure: \(error.localizedDescription)")
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

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
