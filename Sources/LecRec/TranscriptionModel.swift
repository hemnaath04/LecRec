import Foundation

/// Transcription engines LecRec can drive, with the tradeoff stated plainly.
///
/// Parakeet is the best option but it is MLX, so it needs Apple Silicon. Whisper
/// through whisper.cpp runs anywhere including Intel Macs, and scales down far
/// enough for an old machine or a small disk.
enum TranscriptionModel: String, Codable, CaseIterable {
    case parakeetV3
    case whisperTurbo
    case whisperSmall
    case whisperBase
    case whisperTiny

    var label: String {
        switch self {
        case .parakeetV3:   return "Parakeet TDT 0.6B v3"
        case .whisperTurbo: return "Whisper large-v3-turbo"
        case .whisperSmall: return "Whisper small"
        case .whisperBase:  return "Whisper base"
        case .whisperTiny:  return "Whisper tiny"
        }
    }

    /// One line for the picker row.
    var summary: String {
        switch self {
        case .parakeetV3:   return "Best accuracy and fastest. Apple Silicon only."
        case .whisperTurbo: return "Nearly as accurate, runs on any Mac."
        case .whisperSmall: return "Good balance for an older or smaller machine."
        case .whisperBase:  return "Fast and tiny, noticeably rougher."
        case .whisperTiny:  return "Last resort. Too weak for a back row recording."
        }
    }

    var downloadSize: String {
        switch self {
        case .parakeetV3:   return "about 2.5 GB"
        case .whisperTurbo: return "about 1.6 GB"
        case .whisperSmall: return "about 500 MB"
        case .whisperBase:  return "about 150 MB"
        case .whisperTiny:  return "about 75 MB"
        }
    }

    /// Published word error rate, with its caveat. Lower is better.
    var accuracy: String {
        switch self {
        case .parakeetV3:   return "6.3% average WER on the Open ASR leaderboard"
        case .whisperTurbo: return "roughly 3.5 to 5% WER on clean English"
        case .whisperSmall: return "roughly 5 to 7% WER"
        case .whisperBase:  return "roughly 7 to 10% WER"
        case .whisperTiny:  return "10 to 15% WER on difficult audio"
        }
    }

    var requiresAppleSilicon: Bool { self == .parakeetV3 }

    /// What you actually gain and give up. Written for someone deciding, not
    /// for a spec sheet.
    var tradeoff: String {
        switch self {
        case .parakeetV3:
            return """
            What you get: the most accurate option here and by far the fastest, \
            plus the best behaviour on quiet far-field audio. It holds under 2% WER \
            from a clean room down to 25 dB signal to noise, which is the case that \
            matters when you sit at the back of a hall. Handles 25 languages and \
            produces good timestamps.

            What you give up: it only runs on Apple Silicon, and it is the largest \
            download at about 2.5 GB.
            """
        case .whisperTurbo:
            return """
            What you get: accuracy close to the best on clean English, and it runs on \
            any Mac including Intel. 99 languages, the widest coverage here.

            What you give up: slower than Parakeet, and it degrades faster as the room \
            gets noisy, so a back row recording will come back rougher. Expect more \
            garbled numbers and proper nouns, which means a longer gaps section in \
            your notes.
            """
        case .whisperSmall:
            return """
            What you get: a sensible middle. About 500 MB, comfortable on an older \
            Mac or a full disk, and still usable for a clear lecture.

            What you give up: noticeably more errors than turbo, concentrated exactly \
            where they hurt: technical terms, names and numbers. Lean harder on the \
            slide deck to correct them.
            """
        case .whisperBase:
            return """
            What you get: a 150 MB download that transcribes quickly on almost \
            anything.

            What you give up: real accuracy. Roughly 7 to 10% WER means about one word \
            in twelve is wrong, and formulas and technical vocabulary suffer most. Use \
            this when disk or CPU is the binding constraint, not by preference.
            """
        case .whisperTiny:
            return """
            What you get: 75 MB and near-instant transcription.

            What you give up: too much for this job. At 10 to 15% WER on difficult \
            audio, a lecture recorded from the back of a hall will come back with \
            enough errors that the note is built mostly from the slide deck. Only \
            worth using to check that your recording captured sound at all.
            """
        }
    }

    // MARK: - Execution

    var binaryName: String {
        self == .parakeetV3 ? "parakeet-mlx" : "whisper-cli"
    }

    var installHint: String {
        self == .parakeetV3
            ? "uv tool install parakeet-mlx -U"
            : "brew install whisper-cpp"
    }

    /// whisper.cpp model file, downloaded on first use.
    var whisperModelName: String? {
        switch self {
        case .parakeetV3:   return nil
        case .whisperTurbo: return "large-v3-turbo"
        case .whisperSmall: return "small"
        case .whisperBase:  return "base"
        case .whisperTiny:  return "tiny"
        }
    }

    static var isAppleSilicon: Bool {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return machine.hasPrefix("arm")
    }

    /// Models this machine can actually run.
    static var available: [TranscriptionModel] {
        allCases.filter { !$0.requiresAppleSilicon || isAppleSilicon }
    }

    static var recommended: TranscriptionModel {
        isAppleSilicon ? .parakeetV3 : .whisperTurbo
    }
}
