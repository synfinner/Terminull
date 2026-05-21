import AppKit
import SwiftUI

struct ConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    private let existingProfile: ConnectionProfile?
    private let keychain = KeychainService()

    @State private var name: String
    @State private var host: String
    @State private var username: String
    @State private var port: Int
    @State private var keyPath: String
    @State private var rememberPassphrase: Bool
    @State private var keyPassphrase: String = ""
    @State private var validationMessage: String?

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    init(profile: ConnectionProfile?) {
        existingProfile = profile
        _name = State(initialValue: profile?.name ?? "")
        _host = State(initialValue: profile?.host ?? "")
        _username = State(initialValue: profile?.username ?? NSUserName())
        _port = State(initialValue: profile?.port ?? 22)
        _keyPath = State(initialValue: profile?.identityFilePath ?? "")
        _rememberPassphrase = State(initialValue: profile?.storesKeyPassphrase ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                ConnectionFieldRow("Name") {
                    TextField("Production", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                ConnectionFieldRow("Host") {
                    TextField("example.com", text: $host)
                        .textFieldStyle(.roundedBorder)
                }

                ConnectionFieldRow("User") {
                    TextField(NSUserName(), text: $username)
                        .textFieldStyle(.roundedBorder)
                }

                ConnectionFieldRow("Port") {
                    HStack(spacing: 6) {
                        TextField("22", value: $port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)

                        Stepper("Port", value: $port, in: 1...65535)
                            .labelsHidden()

                        Spacer(minLength: 0)
                    }
                }

                ConnectionFieldRow("SSH Key") {
                    HStack(spacing: 8) {
                        TextField("Optional", text: $keyPath)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            chooseKey()
                        } label: {
                            Image(systemName: "folder")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.bordered)
                        .help("Choose SSH Key")
                    }
                }

                ConnectionFieldRow("Keychain") {
                    Toggle("Save key passphrase", isOn: $rememberPassphrase)
                        .toggleStyle(.checkbox)
                }

                if rememberPassphrase {
                    ConnectionFieldRow("Passphrase") {
                        SecureField(existingProfile?.storesKeyPassphrase == true ? "Leave blank to keep current" : "Key passphrase", text: $keyPassphrase)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, ConnectionEditorMetrics.labelWidth + 8)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider()

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(chrome.primaryText)
        .background(chrome.windowBackground.color)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(chrome.iconText)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(chrome.controlFill.color)
                }

            Text(existingProfile == nil ? "Add SSH Connection" : "Edit SSH Connection")
                .font(.title3.weight(.semibold))

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.title = "Choose SSH Key"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")

        if panel.runModal() == .OK, let url = panel.url {
            keyPath = url.path
        }
    }

    private func save() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            validationMessage = "Host is required."
            return
        }

        let id = existingProfile?.id ?? UUID()
        let shouldKeepExistingPassphrase = keyPassphrase.isEmpty && existingProfile?.storesKeyPassphrase == true && rememberPassphrase
        let shouldStorePassphrase = rememberPassphrase && (!keyPassphrase.isEmpty || shouldKeepExistingPassphrase)

        let profile = ConnectionProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: trimmedHost,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            identityFilePath: keyPath.trimmingCharacters(in: .whitespacesAndNewlines),
            storesKeyPassphrase: shouldStorePassphrase,
            lastConnectedAt: existingProfile?.lastConnectedAt
        )

        do {
            if shouldStorePassphrase && !keyPassphrase.isEmpty {
                let previousSecret = try? keychain.readSecret(account: id.uuidString)
                try keychain.saveSecret(keyPassphrase, account: id.uuidString)

                guard connectionStore.upsert(profile) else {
                    if let previousSecret {
                        try? keychain.saveSecret(previousSecret, account: id.uuidString)
                    } else {
                        keychain.deleteSecret(account: id.uuidString)
                    }
                    validationMessage = "Could not save connection."
                    return
                }
            } else {
                guard connectionStore.upsert(profile) else {
                    validationMessage = "Could not save connection."
                    return
                }

                if !shouldStorePassphrase {
                    keychain.deleteSecret(account: id.uuidString)
                }
            }
            dismiss()
        } catch {
            validationMessage = "Could not save passphrase: \(error.localizedDescription)"
        }
    }
}

private enum ConnectionEditorMetrics {
    static let labelWidth: CGFloat = 86
}

private struct ConnectionFieldRow<Content: View>: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore

    private let title: String
    private let labelWidth: CGFloat
    private let content: Content

    init(
        _ title: String,
        labelWidth: CGFloat = ConnectionEditorMetrics.labelWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.labelWidth = labelWidth
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(preferencesStore.preferences.theme.chrome.secondaryText)
                .frame(width: labelWidth, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
