import Foundation

final class ConnectionStore: ObservableObject {
    @Published private(set) var profiles: [ConnectionProfile] = []

    private let storageURL: URL

    init(storageURL: URL = SupportPaths.applicationSupportDirectory.appendingPathComponent("connections.json")) {
        self.storageURL = storageURL
        secureStorageLocation()
        load()
    }

    @discardableResult
    func upsert(_ profile: ConnectionProfile) -> Bool {
        var updatedProfiles = profiles
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            updatedProfiles[index] = profile
        } else {
            updatedProfiles.append(profile)
        }
        updatedProfiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        guard save(updatedProfiles) else {
            return false
        }

        profiles = updatedProfiles
        return true
    }

    func markConnected(_ profile: ConnectionProfile) {
        var updated = profile
        updated.lastConnectedAt = Date()
        upsert(updated)
    }

    @discardableResult
    func delete(_ profile: ConnectionProfile) -> Bool {
        let updatedProfiles = profiles.filter { $0.id != profile.id }
        guard save(updatedProfiles) else {
            return false
        }

        profiles = updatedProfiles
        KeychainService().deleteSecret(account: profile.id.uuidString)
        return true
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
