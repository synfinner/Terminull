import AppKit
import SwiftUI

struct ConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    private let existingProfile: ConnectionProfile?
    private let keychain: any KeychainManaging

    @State private var name: String
    @State private var host: String
    @State private var username: String
    @State private var loginPassword: String = ""
    @State private var removeLoginPassword: Bool = false
    @State private var port: Int
    @State private var keyPath: String
    @State private var rememberPassphrase: Bool
    @State private var keyPassphrase: String = ""
    @State private var validationMessage: String?
    @State private var showingPassphrasePrompt = false
    @State private var skippedPassphrasePrompt = false

    private var chrome: AppChromePalette {
        preferencesStore.preferences.theme.chrome
    }

    init(profile: ConnectionProfile?, keychain: any KeychainManaging = KeychainService()) {
        existingProfile = profile
        self.keychain = keychain
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

                ConnectionFieldRow("Password") {
                    SecureField(existingProfile?.storesLoginPassword == true ? "Leave blank to keep saved" : "Optional", text: $loginPassword)
                        .textFieldStyle(.roundedBorder)
                }

                if existingProfile?.storesLoginPassword == true {
                    ConnectionFieldRow("") {
                        Toggle("Remove saved login password", isOn: $removeLoginPassword)
                            .toggleStyle(.checkbox)
                    }
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
        .alert("Save SSH Key Passphrase?", isPresented: $showingPassphrasePrompt) {
            Button("Save Passphrase") {
                rememberPassphrase = true
                skippedPassphrasePrompt = false
                validationMessage = "Enter the key passphrase to save it to Keychain."
            }

            Button("Continue Without Saving") {
                skippedPassphrasePrompt = true
                save()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Terminull can store this key's passphrase in the macOS Keychain so the saved SSH connection can load it before connecting.")
        }
        .onChange(of: keyPath) { _, _ in
            skippedPassphrasePrompt = false
        }
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

        let trimmedKeyPath = keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if ConnectionEditorPassphrasePrompt.shouldPromptBeforeSaving(
            keyPath: trimmedKeyPath,
            rememberPassphrase: rememberPassphrase,
            existingStoresKeyPassphrase: existingProfile?.storesKeyPassphrase == true,
            skippedPrompt: skippedPassphrasePrompt
        ) {
            showingPassphrasePrompt = true
            return
        }

        let id = existingProfile?.id ?? UUID()
        let hasExistingPassphrase = existingProfile?.storesKeyPassphrase == true
            && keychain.hasSecret(account: ConnectionSecretAccount.keyPassphrase(for: id))
        let shouldKeepExistingPassphrase = keyPassphrase.isEmpty && hasExistingPassphrase && rememberPassphrase
        if rememberPassphrase && keyPassphrase.isEmpty && !shouldKeepExistingPassphrase {
            validationMessage = "Key passphrase is required when saving to Keychain."
            return
        }
        let shouldStorePassphrase = rememberPassphrase && (!keyPassphrase.isEmpty || shouldKeepExistingPassphrase)
        let loginPasswordDecision = ConnectionEditorLoginPasswordDecision.resolve(
            enteredPassword: loginPassword,
            existingStoresLoginPassword: existingProfile?.storesLoginPassword == true,
            removeSavedPassword: removeLoginPassword
        )

        let profile = ConnectionProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: trimmedHost,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            identityFilePath: trimmedKeyPath,
            storesKeyPassphrase: shouldStorePassphrase,
            storesLoginPassword: loginPasswordDecision.storesLoginPassword,
            lastConnectedAt: existingProfile?.lastConnectedAt
        )

        let keyPassphraseUpdate: ConnectionKeychainUpdate
        if shouldStorePassphrase, !keyPassphrase.isEmpty {
            keyPassphraseUpdate = .saveSecret(keyPassphrase)
        } else if !shouldStorePassphrase, existingProfile?.storesKeyPassphrase == true {
            keyPassphraseUpdate = .deleteSecret
        } else {
            keyPassphraseUpdate = .unchanged
        }

        guard connectionStore.upsert(
            profile,
            keychainUpdates: [
                ConnectionKeychainMutation(
                    account: ConnectionSecretAccount.keyPassphrase(for: profile.id),
                    update: keyPassphraseUpdate
                ),
                ConnectionKeychainMutation(
                    account: ConnectionSecretAccount.loginPassword(for: profile.id),
                    update: loginPasswordDecision.keychainUpdate
                )
            ]
        ) else {
            validationMessage = "Could not save connection."
            return
        }

        dismiss()
    }
}

enum ConnectionEditorLoginPasswordDecision {
    static func resolve(
        enteredPassword: String,
        existingStoresLoginPassword: Bool,
        removeSavedPassword: Bool
    ) -> (storesLoginPassword: Bool, keychainUpdate: ConnectionKeychainUpdate) {
        if removeSavedPassword {
            return (false, .deleteSecret)
        }
        if !enteredPassword.isEmpty {
            return (true, .saveSecret(enteredPassword))
        }
        if existingStoresLoginPassword {
            return (true, .unchanged)
        }
        return (false, .unchanged)
    }
}

enum ConnectionEditorPassphrasePrompt {
    static func shouldPromptBeforeSaving(
        keyPath: String,
        rememberPassphrase: Bool,
        existingStoresKeyPassphrase: Bool,
        skippedPrompt: Bool
    ) -> Bool {
        !keyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !rememberPassphrase
            && !existingStoresKeyPassphrase
            && !skippedPrompt
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
