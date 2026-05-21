import Foundation

enum SupportPaths {
    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("Terminull", isDirectory: true)
        do {
            try FileManager.default.createPrivateDirectory(at: directory)
        } catch {
            NSLog("Terminull failed to prepare application support directory: \(error.localizedDescription)")
        }
        return directory
    }
}

extension FileManager {
    func createPrivateDirectory(at url: URL) throws {
        try createDirectory(at: url, withIntermediateDirectories: true)
        try setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func applyOwnerOnlyFilePermissions(at url: URL) throws {
        try setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
