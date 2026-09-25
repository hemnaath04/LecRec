import Foundation

/// Decides whether a transcript is worth spending a write-up on.
///
/// Nothing reaches Notion without the user pressing the button, but the queue
/// should not present junk as if it were a lecture. Three real cases have now
/// occurred: a 39 second take from a mis-clicked button, a 51 second orphan, and
/// an hour of audio that transcribed to 97 percent the literal string
/// NON-ENGLISH SPEECH because the microphone could not reach the lecturer, and
/// an 81 minute file in which the Continuity microphone quietly stopped
/// delivering samples and Whisper filled 45 minutes of digital silence with one
/// fluent English sentence repeated 83 times. The last case passed every check
/// here, because the filler was real words and it ran to the end of the audio.
enum QualityGate {
    enum Verdict {
        case good
        /// Publishable, but the user should see the caveat first.
        case questionable(String)
        /// Almost certainly not a lecture worth writing up.
        case poor(String)

        var isBlocking: Bool { if case .poor = self { return true }; return false }

        var message: String? {
            switch self {
            case .good: return nil
            case .questionable(let reason), .poor(let reason): return reason
            }
        }
    }

    /// A lecture shorter than this is a test press, not a class.
    static let minimumDuration: TimeInterval = 5 * 60
    /// Below this share of real words, the transcript carries no content.
    static let minimumUsableShare = 0.35
    /// Above this share of cues sitting inside a repeated run, the transcript is
    /// a decoder loop over silence rather than speech. Measured on real files:
    /// healthy lectures score 0.00 and 0.09, the two known broken ones 0.59 and 0.97.
    static let maximumLoopShare = 0.30

    static func assess(duration: TimeInterval, transcript: URL) -> Verdict {
        if duration < 60 {
            return .poor(String(format: "Only %.0f seconds long. This looks like a test press rather than a lecture.", duration))
        }

        let stats = transcriptStats(transcript)
        if stats.totalCues == 0 {
            return .poor("The transcript is empty.")
        }

        if stats.usableShare < minimumUsableShare {
            return .poor(String(
                format: "Only %.0f%% of the transcript is real speech, the rest is unusable markers. "
                    + "The microphone was probably too far from the speaker. "
                    + "A note built from this would be mostly invented.",
                stats.usableShare * 100))
        }

        // A loop is checked before length and word count because it inflates
        // both: the filler is fluent, so it reads as real speech, and it runs to
        // the end of the file, so coverage reports 100 percent.
        if stats.loopShare > maximumLoopShare {
            return .poor(String(
                format: "%.0f%% of the transcript is one line repeating, the longest run being %d times. "
                    + "That is the transcriber filling silence, not the lecture. "
                    + "The microphone most likely stopped delivering audio partway through.",
                stats.loopShare * 100, stats.longestRun))
        }

        if duration < minimumDuration {
            return .questionable(String(
                format: "Only %.0f minutes long. Write it up if that is really the whole class.",
                duration / 60))
        }

        if stats.usableShare < 0.7 {
            return .questionable(String(
                format: "%.0f%% of the transcript is real speech. Expect gaps, and lean on the slide deck.",
                stats.usableShare * 100))
        }

        if stats.loopShare > 0.15 {
            return .questionable(String(
                format: "%.0f%% of the transcript is one line repeating. Some of this recording is silence.",
                stats.loopShare * 100))
        }

        if stats.realWords < 200 {
            return .questionable("Only \(stats.realWords) words were transcribed. That is very little for a lecture.")
        }

        return .good
    }

    struct Stats {
        var totalCues = 0
        var usableCues = 0
        var realWords = 0
        /// Cues sitting inside a run of four or more identical consecutive lines.
        var loopedCues = 0
        var longestRun = 0
        var usableShare: Double { totalCues == 0 ? 0 : Double(usableCues) / Double(totalCues) }
        var loopShare: Double { totalCues == 0 ? 0 : Double(loopedCues) / Double(totalCues) }
    }

    /// Counts cues that carry words against cues that are only a marker. Whisper
    /// emits `[NON-ENGLISH SPEECH]` and `[BLANK_AUDIO]` for audio it cannot parse,
    /// and a transcript made almost entirely of those looks full but says nothing.
    static func transcriptStats(_ url: URL) -> Stats {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return Stats() }
        var stats = Stats()
        // Consecutive identical lines, tracked as we go. Scattered repeats are
        // normal speech ("Okay." lands 23 times in a healthy lecture); a run of
        // them back to back is the decoder stuck on silence.
        var previous: String?
        var runLength = 0
        func flushRun() {
            stats.longestRun = max(stats.longestRun, runLength)
            if runLength >= 4 { stats.loopedCues += runLength }
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || Int(line) != nil || line.contains("-->") { continue }
            stats.totalCues += 1
            if line == previous {
                runLength += 1
            } else {
                flushRun()
                previous = line
                runLength = 1
            }
            let stripped = line
                // The hyphen matters: the marker that actually shows up is
                // [NON-ENGLISH SPEECH], and a character class without it scored
                // an unusable transcript as 100 percent clean.
                .replacingOccurrences(of: #"\[[A-Za-z_\- ]+\]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if stripped.count > 1 {
                stats.usableCues += 1
                stats.realWords += stripped.split(separator: " ").count
            }
        }
        flushRun()
        return stats
    }
}
