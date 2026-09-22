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
    case awaitingDeck = "Waiting for your slide deck"
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

    /// Phase one, automatic when recording stops: make a transcript and stop.
    /// The note is deliberately not written yet, so the slide deck can still be
    /// attached before the expensive and hard-to-redo step.
    func transcribe(lecture: Lecture) async throws -> PendingLecture {
        let dir = URL(fileURLWithPath: settings.notesRoot)
            .appendingPathComponent(lecture.course.slug, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let cleaned = dir.appendingPathComponent("audio/\(lecture.baseName)-clean.wav")
        let srt = dir.appendingPathComponent("transcripts/\(lecture.baseName).srt")

        advance(.cleaning, "Reducing room noise and lifting quiet speech")
        try FileManager.default.createDirectory(
            at: cleaned.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await AudioClean.run(input: lecture.audioURL, output: cleaned,
                                 denoise: settings.denoise, log: onLog)

        advance(.transcribing, "Running \(settings.transcriptionModel.label) on device")
        try FileManager.default.createDirectory(
            at: srt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await Transcriber.run(input: cleaned, outputSRT: srt,
                                  model: settings.transcriptionModel, log: onLog)

        advance(.checking, "Comparing transcript length against the recording")
        let report = CoverageReport(
            audioDuration: lecture.audioDuration,
            transcriptEnd: SRT.lastTimestamp(of: srt) ?? 0)
        onLog?(report.summary)

        // The cleaned copy is only an input to transcription, and it is large.
        try? FileManager.default.removeItem(at: cleaned)

        return PendingLecture(
            courseSlug: lecture.course.slug,
            courseName: lecture.course.name,
            notionCourse: lecture.course.notionCourse,
            date: lecture.date,
            slug: lecture.slug,
            audioPath: lecture.audioURL.path,
            transcriptPath: srt.path,
            audioDuration: lecture.audioDuration,
            coverage: report.audioDuration > 0 ? report.coverage : nil,
            deckPath: nil,
            transcribedAt: Date())
    }

    /// Phase two, started by the user once they have decided about the deck.
    func writeUp(_ pending: PendingLecture) async throws -> URL {
        let lecture = pending.lecture
        let report = CoverageReport(audioDuration: pending.audioDuration,
                                    transcriptEnd: (pending.coverage ?? 1) * pending.audioDuration)

        if settings.linkPreviousLectures {
            advance(.recalling, "Reading the last \(settings.continuityLookback) notes for this course")
        }
        advance(.reasoning, lecture.deckPath == nil
                ? "Writing from the transcript alone"
                : "Cross-checking the transcript against your deck")

        let runner = ClaudeRunner(settings: settings)
        let noteURL = try await runner.buildNote(
            lecture: lecture, transcript: pending.transcriptURL, coverage: report,
            onLog: onLog, onStage: { [weak self] detail in
                self?.advance(.reasoning, detail)
            })

        if settings.archiveAudioAfterProcessing {
            if let result = try? await AudioArchive.compressAndPrune(
                source: lecture.audioURL, alsoRemove: [], log: onLog) {
                onLog?("Kept \(result.archive.lastPathComponent), freed \(result.bytesFreed / 1_000_000) MB")
            }
        }

        advance(.done, "Published to \(settings.destination.label)")
        return noteURL
    }

    private func advance(_ stage: PipelineStage, _ detail: String) {
        self.stage = stage
        DispatchQueue.main.async { self.onStage?(stage, detail) }
    }
}
