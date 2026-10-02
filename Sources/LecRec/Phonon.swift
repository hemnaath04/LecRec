import Foundation

/// Phonon-2, the transcriber LecRec actually uses.
///
/// Measured on this user's own lectures rather than a benchmark. On a clean
/// 48.7 minute recording it produced 4,692 words against whisper small.en's
/// 4,406, with zero unusable marker cues against whisper's 57. On a 71.8 minute
/// lecture that whisper rendered 97 percent `[NON-ENGLISH SPEECH]` it produced
/// 6,147 words of coherent content.
///
/// The cost of that is the thing to design around: where the audio really is
/// unintelligible Phonon does not say so. It guesses, fluently and
/// confidently, which is harder to spot than a marker. QualityGate cannot see
/// it either, because the guesses do not repeat. Prompt.swift therefore makes
/// the write-up model responsible for calling it out.
enum Phonon {
    /// Cue grouping, tuned on a real lecture. Breaking on every pause alone
    /// produced three-word cues out of hesitant speech, so a cue has to be ripe
    /// before a pause is allowed to end it.
    private static let maxSeconds = 9.0
    private static let maxCharacters = 180
    private static let pauseSeconds = 1.4
    private static let minWords = 6
    private static let minSeconds = 2.0

    struct Word: Decodable {
        let text: String
        let start: Double
        let end: Double
    }

    private struct Output: Decodable {
        let text: String
        let words: [Word]
        let durationSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case text, words
            case durationSeconds = "duration_seconds"
        }
    }

    static func transcribe(input: URL, outputSRT: URL, hotwords: [String],
                           log: ((String) -> Void)?) async throws {
        let binary = try Shell.require("phonon", hint: installHint)
        let jsonURL = outputSRT.deletingPathExtension()
            .appendingPathExtension("phonon.json")

        // phonon prints JSON on stdout and its progress on stderr, and Shell
        // merges both into one pipe, so the JSON is redirected to a file by a
        // shell rather than picked back out of the mixed stream.
        var command = quote(binary) + " transcribe " + quote(input.path) + " --json"
        if !hotwords.isEmpty {
            command += " --hotwords " + quote(hotwords.joined(separator: ","))
        }
        command += " > " + quote(jsonURL.path)
        try await Shell.run("/bin/sh", ["-c", command], log: log)

        let data = try Data(contentsOf: jsonURL)
        let output = try JSONDecoder().decode(Output.self, from: data)
        guard !output.words.isEmpty else {
            throw Shell.Failed(tool: "phonon", code: 0,
                               output: "the transcript came back with no words")
        }
        let srt = srtText(words: output.words)
        try srt.write(to: outputSRT, atomically: true, encoding: .utf8)
        log?("transcribed \(output.words.count) words into \(outputSRT.lastPathComponent)")
    }

    static func srtText(words: [Word]) -> String {
        var cues: [[Word]] = []
        var current: [Word] = []
        for word in words {
            if let first = current.first, let last = current.last {
                let span = word.end - first.start
                let pause = word.start - last.end
                let text = current.map(\.text).joined(separator: " ")
                let ripe = current.count >= minWords && span >= minSeconds
                let sentenceEnded = text.hasSuffix(".") || text.hasSuffix("?") || text.hasSuffix("!")
                if span > maxSeconds || text.count > maxCharacters
                    || (ripe && (pause > pauseSeconds || (sentenceEnded && span > 4.0))) {
                    cues.append(current)
                    current = []
                }
            }
            current.append(word)
        }
        if !current.isEmpty { cues.append(current) }

        var lines: [String] = []
        for (index, cue) in cues.enumerated() {
            guard let first = cue.first, let last = cue.last else { continue }
            lines.append("\(index + 1)")
            lines.append("\(stamp(first.start)) --> \(stamp(last.end))")
            lines.append(cue.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func stamp(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let hours = Int(total) / 3600
        let minutes = Int(total) % 3600 / 60
        let secs = Int(total) % 60
        var milli = Int(((total - total.rounded(.down)) * 1000).rounded())
        if milli > 999 { milli = 999 }
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milli)
    }

    /// Single-quote for /bin/sh, closing and reopening around any quote inside.
    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static let installHint = """
        uv tool install fermion-research --with mlx --with mlx-audio --with mlx-lm \
        --with soundfile --with scipy --with zstandard
        """
}
