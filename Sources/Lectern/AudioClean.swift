import Foundation

enum AudioClean {
    /// High-pass removes HVAC rumble, afftdn pulls the noise floor down, and
    /// speechnorm lifts quiet speech without amplifying the silence between
    /// sentences. Tuned for a back-row recording off a laptop mic.
    static let filterChain = "highpass=f=90,afftdn=nr=12:nf=-30,speechnorm=e=12.5:r=0.0005:l=1"

    static func run(input: URL, output: URL, denoise: Bool,
                    log: ((String) -> Void)?) async throws {
        let ffmpeg = try Shell.require("ffmpeg", hint: "brew install ffmpeg")
        var arguments = ["-nostdin", "-y", "-i", input.path]
        if denoise { arguments += ["-af", filterChain] }
        // 16 kHz mono is what the ASR model consumes; anything more is discarded.
        arguments += ["-ac", "1", "-ar", "16000", output.path]
        try await Shell.run(ffmpeg, arguments, log: log)
    }

    /// Duration in seconds, read back from the file rather than trusted from
    /// the recorder's frame count.
    static func duration(of url: URL) async throws -> TimeInterval {
        let ffprobe = try Shell.require("ffprobe", hint: "brew install ffmpeg")
        let output = try await Shell.run(ffprobe, [
            "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", url.path,
        ])
        return TimeInterval(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

enum Transcriber {
    /// `--output-template` names the file directly, so there is no rename step
    /// and no chance of colliding with a previous run's output.
    static func run(input: URL, outputSRT: URL, log: ((String) -> Void)?) async throws {
        let parakeet = try Shell.require(
            "parakeet-mlx", hint: "uv tool install parakeet-mlx -U")
        let stem = outputSRT.deletingPathExtension().lastPathComponent
        try await Shell.run(parakeet, [
            input.path,
            "--output-format", "srt",
            "--output-dir", outputSRT.deletingLastPathComponent().path,
            "--output-template", stem,
        ], log: log)

        guard FileManager.default.fileExists(atPath: outputSRT.path) else {
            throw Shell.Failed(tool: "parakeet-mlx", code: 0,
                               output: "expected \(outputSRT.lastPathComponent) but it was not written")
        }
    }
}

enum SRT {
    /// End timestamp of the final cue, in seconds.
    static func lastTimestamp(of url: URL) -> TimeInterval? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let pattern = #"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last else { return nil }

        func group(_ index: Int) -> Double {
            guard let range = Range(last.range(at: index), in: text) else { return 0 }
            return Double(text[range]) ?? 0
        }
        return group(5) * 3600 + group(6) * 60 + group(7) + group(8) / 1000
    }

    /// Plain text of every cue, for handing to a model that does not need timing.
    static func plainText(of url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return false }
                if Int(trimmed) != nil { return false }
                return !trimmed.contains("-->")
            }
            .joined(separator: " ")
    }
}
