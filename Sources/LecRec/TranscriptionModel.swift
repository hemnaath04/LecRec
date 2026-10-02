import Foundation

/// Transcription engines LecRec can drive, with the tradeoff stated plainly.
///
/// Parakeet is the best option but it is MLX, so it needs Apple Silicon. Whisper
/// through whisper.cpp runs anywhere including Intel Macs, and scales down far
/// enough for an old machine or a small disk.
enum TranscriptionModel: String, Codable, CaseIterable {
    case phonon2
    case parakeetV3
    case whisperTurbo
    case whisperSmall
    case whisperBase
    case whisperTiny

    var label: String {
        switch self {
        case .phonon2:      return "Phonon-2"
        case .parakeetV3:   return "Parakeet TDT 0.6B v3"
        case .whisperTurbo: return "Whisper large-v3-turbo"
        case .whisperSmall: return "Whisper small (English)"
        case .whisperBase:  return "Whisper base (English)"
        case .whisperTiny:  return "Whisper tiny (English)"
        }
    }

    /// One line for the picker row.
    var summary: String {
        switch self {
        case .phonon2:      return "Best on quiet far-field audio. Apple Silicon only."
        case .parakeetV3:   return "Strong and fast. Apple Silicon only."
        case .whisperTurbo: return "Nearly as accurate, runs on any Mac."
        case .whisperSmall: return "Best accuracy per megabyte. Runs on any Mac."
        case .whisperBase:  return "Fast and tiny, noticeably rougher."
        case .whisperTiny:  return "Last resort. Too weak for a back row recording."
        }
    }

    var downloadSize: String {
        switch self {
        case .phonon2:      return "about 164 MB"
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
        case .phonon2:      return "5.21% average WER on the Open ASR leaderboard, 9.37% on AMI"
        case .parakeetV3:   return "6.3% average WER on the Open ASR leaderboard"
        case .whisperTurbo: return "roughly 3.5 to 5% WER on clean English"
        case .whisperSmall: return "5.9% WER measured on a clean English sample"
        case .whisperBase:  return "9.6% WER measured on the same sample"
        case .whisperTiny:  return "10 to 15% WER on difficult audio"
        }
    }

    var requiresAppleSilicon: Bool { self == .parakeetV3 || self == .phonon2 }

    /// What you actually gain and give up. Written for someone deciding, not
    /// for a spec sheet.
    var tradeoff: String {
        switch self {
        case .phonon2:
            return """
            What you get: the best results measured on this user's own lectures, not \
            on a benchmark. On a clean 48.7 minute recording it transcribed 4,692 words \
            against Whisper small's 4,406, with none of Whisper's 57 unusable marker \
            cues. On a 71.8 minute lecture that Whisper returned as 97 percent \
            [NON-ENGLISH SPEECH], it recovered 6,147 words of coherent content. It is \
            164 MB, a quantised Parakeet TDT 0.6B v3, and scores 9.37% on AMI, the \
            far-field meeting benchmark closest to a lecture hall, against Whisper \
            large-v3-turbo's 13.88%.

            What you give up: honesty about silence. Where the audio is genuinely \
            unintelligible it does not emit a marker, it guesses, and the guess reads \
            as fluent English. The write-up model is told to find and quarantine those \
            stretches, but a note from a bad recording still needs your eyes. \
            English only, Apple Silicon only.
            """
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
            What you get: the best accuracy per megabyte here. On a clean English \
            sample it measured 5.9% WER, slightly ahead of Parakeet, at 480 MB and \
            under 5 seconds for 92 seconds of audio. Runs on any Mac.

            What you give up: this was measured on clean speech. Parakeet's real \
            advantage is holding accuracy as the room gets noisy, which a back row \
            recording is, so expect Whisper to fall behind there rather than in a \
            quiet room. English only.
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
        switch self {
        case .phonon2:    return "phonon"
        case .parakeetV3: return "parakeet-mlx"
        default:          return "whisper-cli"
        }
    }

    var installHint: String {
        switch self {
        case .phonon2:    return Phonon.installHint
        case .parakeetV3: return "uv tool install parakeet-mlx -U"
        default:          return "brew install whisper-cpp"
        }
    }

    /// whisper.cpp model file, downloaded on first use.
    var whisperModelName: String? {
        switch self {
        case .phonon2:      return nil
        case .parakeetV3:   return nil
        case .whisperTurbo: return "large-v3-turbo"
        // The .en weights are trained on English only and score better on it than
        // the multilingual ones of the same size. Measured 5.90% against 9.59%
        // for small.en versus base.en on a 271 word sample.
        case .whisperSmall: return "small.en"
        case .whisperBase:  return "base.en"
        case .whisperTiny:  return "tiny.en"
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
        isAppleSilicon ? .phonon2 : .whisperTurbo
    }
}
