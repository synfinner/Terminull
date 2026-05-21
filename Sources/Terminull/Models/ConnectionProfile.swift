import Foundation

struct ConnectionProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var username: String
    var port: Int
    var identityFilePath: String
    var storesKeyPassphrase: Bool
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        username: String,
        port: Int = 22,
        identityFilePath: String = "",
        storesKeyPassphrase: Bool = false,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
        self.port = port
        self.identityFilePath = identityFilePath
        self.storesKeyPassphrase = storesKeyPassphrase
        self.lastConnectedAt = lastConnectedAt
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }
        return host
    }

    var target: String {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUser.isEmpty {
            return host
        }
        return "\(trimmedUser)@\(host)"
    }
}
