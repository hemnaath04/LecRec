import Foundation

/// One lecture moving through record, clean, transcribe, cross-check, publish.
struct Lecture {
    var course: Course
    var date: Date
    /// "attention-and-transformers", or empty to let Claude name it from the content.
    var slug: String
    var audioURL: URL
    var audioDuration: TimeInterval
    var deckPath: String?            // optional .pptx / .pdf the user attached

    var dateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var baseName: String { slug.isEmpty ? dateStamp : "\(dateStamp)-\(slug)" }

    /// True when Claude picks the filename, so the caller must glob for it.
    var needsGeneratedSlug: Bool { slug.isEmpty }
}

enum PipelineStage: String {
    case idle = "Idle"
    case recording = "Recording"
    case cleaning = "Cleaning audio"
    case transcribing = "Transcribing"
    case checking = "Checking coverage"
    case recalling = "Recalling earlier lectures"
    case reasoning = "Building the note"
    case publishing = "Publishing"
    case done = "Done"
    case failed = "Failed"
}

/// Result of comparing transcript length against the recording length. A short
/// transcript is the exact failure that cost a third of the 2026-09-15 lecture,
/// so it is surfaced before publish rather than discovered afterwards.
struct CoverageReport {
    var audioDuration: TimeInterval
    var transcriptEnd: TimeInterval

    var coverage: Double {
        audioDuration > 0 ? min(1, transcriptEnd / audioDuration) : 0
    }

    var isSuspect: Bool { coverage < 0.95 }

    var summary: String {
        let pct = Int((coverage * 100).rounded())
        let audio = Self.clock(audioDuration)
        let end = Self.clock(transcriptEnd)
        if isSuspect {
            return "Transcript covers \(pct)% of the audio (ends \(end) of \(audio)). Flag this in the note."
        }
        return "Transcript covers \(pct)% of the audio (\(end) of \(audio))."
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

/// Orchestrates the whole run. Every external binary is invoked through Shell so
/// a missing dependency surfaces as a readable message rather than a crash.
final class Pipeline {
    private(set) var stage: PipelineStage = .idle
    var onStage: ((PipelineStage, String) -> Void)?
    var onLog: ((String) -> Void)?

    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    func run(lecture: Lecture) async throws -> URL {
        let dir = URL(fileURLWithPath: settings.notesRoot)
            .appendingPathComponent(lecture.course.slug, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let cleaned = dir.appendingPathComponent("audio/\(lecture.baseName)-clean.wav")
        let srt = dir.appendingPathComponent("transcripts/\(lecture.baseName).srt")

        // 1. Clean
        advance(.cleaning, "Reducing room noise and lifting quiet speech")
        try FileManager.default.createDirectory(
            at: cleaned.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await AudioClean.run(input: lecture.audioURL, output: cleaned,
                                 denoise: settings.denoise, log: onLog)

        // 2. Transcribe
        advance(.transcribing, "Running parakeet-mlx on device")
        try FileManager.default.createDirectory(
            at: srt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await Transcriber.run(input: cleaned, outputSRT: srt, log: onLog)

        // 3. Coverage
        advance(.checking, "Comparing transcript length against the recording")
        let report = CoverageReport(
            audioDuration: lecture.audioDuration,
            transcriptEnd: SRT.lastTimestamp(of: srt) ?? 0)
        onLog?(report.summary)

        // 4. Cross-check and write the note, via Claude Code and the course-notes skill
        if settings.linkPreviousLectures {
            advance(.recalling, "Reading the last \(settings.continuityLookback) notes for this course")
        }
        advance(.reasoning, "Claude Code is cross-checking transcript, deck and notes")
        let runner = ClaudeRunner(settings: settings)
        let noteURL = try await runner.buildNote(
            lecture: lecture, transcript: srt, coverage: report,
            onLog: onLog, onStage: { [weak self] detail in
                self?.advance(.reasoning, detail)
            })

        advance(.done, "Published to \(settings.destination.label)")
        return noteURL
    }

    private func advance(_ stage: PipelineStage, _ detail: String) {
        self.stage = stage
        DispatchQueue.main.async { self.onStage?(stage, detail) }
    }
}
