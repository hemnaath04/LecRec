import AppKit

/// Opening a lecture recording should play it, not file it away.
///
/// The system handler for m4a is Music.app, which imports the lecture into the
/// user's music library, and on this machine the handler for md turned out to be
/// a developer tool that opened to a blank window. Both are reasonable system
/// defaults and both are wrong for a lecture, so LecRec asks for the app it
/// wants by bundle id and only falls back to the default when that app is gone.
enum Media {
    /// QuickTime plays a file and leaves it where it is, which is what you want
    /// when checking whether a recording is worth writing up.
    private static let player = "com.apple.QuickTimePlayerX"

    static func play(_ url: URL) {
        open(url, preferring: player)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func open(_ url: URL, preferring bundleID: String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Diagnostics.log("cannot open \(url.lastPathComponent), the file is gone")
            NSSound.beep()
            return
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
                if let error {
                    Diagnostics.log("\(bundleID) refused \(url.lastPathComponent): \(error.localizedDescription)")
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                }
            }
            return
        }
        NSWorkspace.shared.open(url)
    }
}
