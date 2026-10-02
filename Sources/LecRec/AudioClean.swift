import Foundation

enum AudioClean {
    /// Joins a recording that was split by a mid-lecture input change back into
    /// one file. Without this the continuation segments are orphaned and the
    /// note is silently built from only the first part.
    static func join(_ parts: [URL], into output: URL,
                     log: ((String) -> Void)?) async throws -> URL {
        let present = parts.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard present.count > 1 else { return present.first ?? parts[0] }

        let ffmpeg = try Shell.require("ffmpeg", hint: "brew install ffmpeg")
        let list = output.deletingLastPathComponent()
            .appendingPathComponent("segments-\(UUID().uuidString).txt")
        let body = present
            .map { "file '\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: "\n")
        try body.write(to: list, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: list) }

        log?("Joining \(present.count) recording segments after an input change")
        // Re-encode rather than stream copy: segments can differ in sample rate
        // when the device changes, and a copy would produce a broken file.
        try await Shell.run(ffmpeg, [
            "-nostdin", "-y", "-f", "concat", "-safe", "0", "-i", list.path,
            "-ac", "1", output.path,
        ], log: log)
        return output
    }

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
    /// Routes to Parakeet or whisper.cpp. Both are told to write the same SRT
    /// path so nothing downstream has to know which engine ran.
    static func run(input: URL, outputSRT: URL, model: TranscriptionModel,
                    hotwords: [String] = [],
                    log: ((String) -> Void)?) async throws {
        switch model {
        case .phonon2:
            try await Phonon.transcribe(input: input, outputSRT: outputSRT,
                                        hotwords: hotwords, log: log)
        case .parakeetV3:
            try await runParakeet(input: input, outputSRT: outputSRT, log: log)
        default:
            try await runWhisper(input: input, outputSRT: outputSRT, model: model, log: log)
        }
        guard FileManager.default.fileExists(atPath: outputSRT.path) else {
            throw Shell.Failed(tool: model.binaryName, code: 0,
                               output: "expected \(outputSRT.lastPathComponent) but it was not written")
        }
    }

    private static func runParakeet(input: URL, outputSRT: URL,
                                    log: ((String) -> Void)?) async throws {
        let binary = try Shell.require("parakeet-mlx",
                                       hint: TranscriptionModel.parakeetV3.installHint)
        try await Shell.run(binary, [
            input.path,
            "--output-format", "srt",
            "--output-dir", outputSRT.deletingLastPathComponent().path,
            "--output-template", outputSRT.deletingPathExtension().lastPathComponent,
        ], log: log)
    }

    /// whisper.cpp writes <output-file>.srt, so the prefix is passed without the
    /// extension and the model file is fetched on first use.
    private static func runWhisper(input: URL, outputSRT: URL, model: TranscriptionModel,
                                   log: ((String) -> Void)?) async throws {
        let binary = try Shell.require("whisper-cli", hint: model.installHint)
        guard let name = model.whisperModelName else {
            throw Shell.MissingTool(name: model.label, installHint: model.installHint)
        }
        let modelFile = try await whisperModelFile(named: name, log: log)
        let prefix = outputSRT.deletingPathExtension().path
        try await Shell.run(binary, [
            "-m", modelFile.path,
            "-f", input.path,
            "--output-srt",
            "--output-file", prefix,
            "--print-progress",
        ], log: log)
    }

    /// Models live beside the app's own data, not in the Homebrew prefix, so a
    /// brew upgrade never deletes a 1.6 GB download.
    private static func whisperModelFile(named name: String,
                                         log: ((String) -> Void)?) async throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LecRec/models", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("ggml-\(name).bin")
        if FileManager.default.fileExists(atPath: file.path) { return file }

        log?("Downloading the \(name) model, this happens once.")
        let curl = try Shell.require("curl", hint: "curl ships with macOS")
        let url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(name).bin"
        try await Shell.run(curl, ["-fL", "--retry", "2", "-o", file.path, url], log: log)
        return file
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
