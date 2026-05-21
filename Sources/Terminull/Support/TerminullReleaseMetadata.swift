import Foundation

enum TerminullReleaseMetadata {
    static let version = "0.1.3"
    static let aboutText = "Terminull was built by synfinner. No tracking, no bs, just a terminal emulator with SSH management."
    static let bitcoinAddress = "bc1qqfrapakl4yceqs99k84j3tznjsa9c59mklvsvm"
    static let lightningAddress = "synfinner@cake.cash"
    static let donationText = """
    Donations are accepted via Bitcoin and Bitcoin Lightning.

    On-Chain address:
    \(bitcoinAddress)

    Lightning address:
    \(lightningAddress)
    """
}
