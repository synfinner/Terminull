import Foundation

struct ConnectionProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var username: String
    var port: Int
    var identityFilePath: String
    var storesKeyPassphrase: Bool
    var storesLoginPassword: Bool
    var lastConnectedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case username
        case port
        case identityFilePath
        case storesKeyPassphrase
        case storesLoginPassword
        case lastConnectedAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        username: String,
        port: Int = 22,
        identityFilePath: String = "",
        storesKeyPassphrase: Bool = false,
        storesLoginPassword: Bool = false,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
        self.port = port
        self.identityFilePath = identityFilePath
        self.storesKeyPassphrase = storesKeyPassphrase
        self.storesLoginPassword = storesLoginPassword
        self.lastConnectedAt = lastConnectedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        username = try container.decode(String.self, forKey: .username)
        port = try container.decode(Int.self, forKey: .port)
        identityFilePath = try container.decode(String.self, forKey: .identityFilePath)
        storesKeyPassphrase = try container.decodeIfPresent(Bool.self, forKey: .storesKeyPassphrase) ?? false
        storesLoginPassword = try container.decodeIfPresent(Bool.self, forKey: .storesLoginPassword) ?? false
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
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
