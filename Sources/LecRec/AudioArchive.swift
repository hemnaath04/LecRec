import Foundation

/// Turns the working audio into something worth keeping, then deletes the rest.
///
/// A lecture is captured uncompressed because a recording you cannot redo should
/// not depend on an encoder, but keeping it that way is indefensible: a 100
/// minute lecture is about 1.15 GB raw plus 192 MB of cleaned copy, against 38 MB
/// as AAC. The raw files exist only until the transcript does.
enum AudioArchive {
    /// AAC in an m4a container: transparent for speech at this rate, and it plays
    /// in QuickTime, Finder and on iPhone with nothing installed. Opus is smaller
    /// but macOS will not preview it.
    static let bitrate = "48k"

    struct Result {
        var archive: URL
        var bytesFreed: Int64
        var archiveBytes: Int64

        var summary: String {
            let freed = Double(bytesFreed) / 1e6
            let kept = Double(archiveBytes) / 1e6
            return String(format: "archived %.0f MB of audio to %.0f MB, freed %.0f MB",
                          freed + kept, kept, freed)
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Encodes `source` to m4a beside it, then removes every working file given.
    /// The archive is written and verified before anything is deleted.
    static func compressAndPrune(source: URL,
                                 alsoRemove: [URL],
                                 log: ((String) -> Void)?) async throws -> Result {
        let ffmpeg = try Shell.require("ffmpeg", hint: "brew install ffmpeg")
        let archive = source.deletingPathExtension()
            .deletingLastPathComponent()
            .appendingPathComponent(
                source.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "-raw", with: "") + ".m4a")

        log?("Compressing the recording for the archive")
        try await Shell.run(ffmpeg, [
            "-nostdin", "-y", "-i", source.path,
            "-c:a", "aac", "-b:a", bitrate, "-ac", "1",
            archive.path,
        ], log: nil)

        // Refuse to delete anything unless the archive is real and plausible.
        let archiveBytes = fileSize(archive)
        guard archiveBytes > 10_000 else {
            throw Shell.Failed(tool: "ffmpeg", code: 0,
                               output: "archive was missing or implausibly small, keeping the raw audio")
        }

        var freed: Int64 = 0
        for url in [source] + alsoRemove {
            guard url != archive, FileManager.default.fileExists(atPath: url.path) else { continue }
            let bytes = fileSize(url)
            try? FileManager.default.removeItem(at: url)
            freed += bytes
        }

        let result = Result(archive: archive, bytesFreed: freed, archiveBytes: archiveBytes)
        log?(result.summary)
        Diagnostics.log(result.summary)
        return result
    }
}
