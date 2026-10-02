import Foundation

/// How much room is left for a recording.
///
/// On 2026-10-02 a lecture was captured straight to disk with nothing watching
/// the volume. The disk reached 100 percent, the writer died mid-stream, and
/// about 26 minutes of the class was lost with no warning of any kind. Audio at
/// 48 kHz 16-bit mono costs 5.8 MB a minute, so a 100 minute lecture needs most
/// of a gigabyte, which is exactly the size nobody thinks to check.
enum DiskSpace {
    /// What the volume will actually give us, not the raw free figure. macOS
    /// reports purgeable space as free even though a writer cannot always get
    /// at it in time, so this asks for the importantUsage figure instead.
    static func availableBytes(at url: URL) -> Int64? {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard let values = try? directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        else { return nil }
        return values.volumeAvailableCapacityForImportantUsage
    }

    /// Headroom to leave for everything else: the transcription writes a 16 kHz
    /// copy, the archive writes an m4a, and macOS itself misbehaves badly on a
    /// full volume.
    static let reserveBytes: Int64 = 500 * 1_000_000

    /// The longest lecture worth planning for.
    static let plannedSeconds: Double = 2 * 60 * 60

    /// Warn here, while there is still time to act.
    static let warningBytes: Int64 = 1_000 * 1_000_000
    /// Stop here, so the file is closed properly instead of dying mid-write.
    static let criticalBytes: Int64 = 250 * 1_000_000

    static func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = bytes < 1_000_000_000 ? [.useMB] : [.useGB]
        return formatter.string(fromByteCount: bytes)
    }

    static func minutes(ofRoom bytes: Int64, bytesPerSecond: Double) -> Int {
        guard bytesPerSecond > 0 else { return 0 }
        return Int(Double(bytes) / bytesPerSecond / 60)
    }
}
