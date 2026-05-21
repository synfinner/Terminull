import AppKit
import SwiftUI

@MainActor
enum TerminullAboutPanel {
    private static var panel: NSPanel?

    static func show(theme: TerminalTheme) {
        if let panel {
            panel.contentViewController = NSHostingController(rootView: makeRootView(theme: theme))
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "About Terminull"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.center()
        panel.contentViewController = NSHostingController(rootView: makeRootView(theme: theme))
        panel.isReleasedWhenClosed = false
        self.panel = panel

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func makeRootView(theme: TerminalTheme) -> AboutTerminullView {
        AboutTerminullView(theme: theme) {
            close()
        }
    }

    private static func close() {
        panel?.close()
    }
}

struct AboutTerminullView: View {
    let theme: TerminalTheme
    let onClose: () -> Void

    private var chrome: AppChromePalette {
        theme.chrome
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                appIdentity
                aboutText
                donationPanel
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 24)

            Rectangle()
                .fill(chrome.separator.color)
                .frame(height: 1)

            HStack {
                Text("No analytics. No trackers. No telemetry.")
                    .font(.caption)
                    .foregroundStyle(chrome.tertiaryText)

                Spacer()

                Button("Done") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(width: 500)
        .foregroundStyle(chrome.primaryText)
        .background {
            ZStack {
                chrome.windowBackground.color

                LinearGradient(
                    colors: [
                        chrome.headerTop.color.opacity(chrome.isLight ? 0.58 : 0.42),
                        chrome.windowBackground.color
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var appIdentity: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(chrome.controlStroke.color, lineWidth: 1)
                }
                .shadow(color: .black.opacity(chrome.isLight ? 0.08 : 0.28), radius: 14, y: 8)

            VStack(spacing: 4) {
                Text("Terminull")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(chrome.primaryText)

                Text("Version \(TerminullReleaseMetadata.version)")
                    .font(.callout)
                    .foregroundStyle(chrome.secondaryText)
            }
        }
    }

    private var aboutText: some View {
        Text(TerminullReleaseMetadata.aboutText)
            .font(.callout)
            .foregroundStyle(chrome.secondaryText)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 410)
    }

    private var donationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Donate", systemImage: "bitcoinsign.circle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(chrome.primaryText)

            Text("Donations are accepted via Bitcoin and Bitcoin Lightning.")
                .font(.callout)
                .foregroundStyle(chrome.secondaryText)

            VStack(alignment: .leading, spacing: 10) {
                DonationAddressRow(
                    title: "On-Chain",
                    value: TerminullReleaseMetadata.bitcoinAddress,
                    chrome: chrome
                )

                DonationAddressRow(
                    title: "Lightning",
                    value: TerminullReleaseMetadata.lightningAddress,
                    chrome: chrome
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chrome.controlFill.color)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(chrome.controlStroke.color, lineWidth: 1)
        }
    }
}

private struct DonationAddressRow: View {
    let title: String
    let value: String
    let chrome: AppChromePalette

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(chrome.tertiaryText)

            HStack(spacing: 6) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(chrome.primaryText)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 10)

                Button {
                    copyToPasteboard()
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(didCopy ? Color(nsColor: .systemGreen) : chrome.iconText)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(chrome.controlFill.color)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(chrome.controlStroke.color, lineWidth: 1)
                }
                .help("Copy \(title) address")
            }
        }
    }

    private func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        didCopy = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            didCopy = false
        }
    }
}
