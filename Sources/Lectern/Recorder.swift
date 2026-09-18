import Foundation
import AVFoundation
import CoreAudio

/// Captures the selected input to a CAF file, writing incrementally so a crash
/// leaves a recoverable lecture on disk rather than nothing.
final class Recorder {
    enum RecorderError: LocalizedError {
        case micDenied
        case deviceUnavailable(String)
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case .micDenied:
                return "Microphone access was denied. Grant it in System Settings, Privacy and Security, Microphone."
            case .deviceUnavailable(let name):
                return "Input device \(name) is unavailable."
            case .engineFailed(let detail):
                return "Could not start the audio engine: \(detail)"
            }
        }
    }

    /// Fires on the main queue roughly 10x a second while recording.
    var onLevel: ((Float) -> Void)?
    /// Fires on the main queue once a second with elapsed seconds.
    var onTick: ((TimeInterval) -> Void)?

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var timer: Timer?
    private var startedAt: Date?
    private(set) var outputURL: URL?
    private(set) var isRecording = false

    /// Frames written so far, the authoritative duration source for the coverage check.
    private var framesWritten: AVAudioFramePosition = 0
    private var sampleRate: Double = 48_000

    var duration: TimeInterval {
        sampleRate > 0 ? Double(framesWritten) / sampleRate : 0
    }

    // MARK: - Permission

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: - Lifecycle

    func start(deviceUID: String?, to url: URL) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.micDenied
        }

        if let deviceUID {
            guard let device = AudioDevices.device(uid: deviceUID) else {
                throw RecorderError.deviceUnavailable(deviceUID)
            }
            try setInputDevice(device.id)
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.engineFailed("input format reported \(format.sampleRate) Hz, \(format.channelCount) ch")
        }
        sampleRate = format.sampleRate
        framesWritten = 0

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // CAF rather than WAV: its chunked layout survives an unfinalised header
        // better, and ffmpeg decodes it without complaint.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let audioFile = try AVAudioFile(forWriting: url, settings: settings,
                                        commonFormat: .pcmFormatFloat32, interleaved: false)
        file = audioFile
        outputURL = url

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.file?.write(from: buffer)
            self.framesWritten += AVAudioFramePosition(buffer.frameLength)
            let level = Recorder.normalizedLevel(buffer)
            DispatchQueue.main.async { self.onLevel?(level) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            file = nil
            throw RecorderError.engineFailed(error.localizedDescription)
        }

        startedAt = Date()
        isRecording = true
        let tick = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            self.onTick?(Date().timeIntervalSince(startedAt))
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// Stops capture and returns the finalised file plus its true duration.
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false

        let result = outputURL.map { (url: $0, duration: duration) }
        file = nil          // releasing the AVAudioFile finalises the header
        startedAt = nil
        return result
    }

    // MARK: - Private

    /// Points the engine's input hardware at a specific device.
    private func setInputDevice(_ id: AudioDeviceID) throws {
        guard let unit = engine.inputNode.audioUnit else {
            throw RecorderError.engineFailed("input node exposed no audio unit")
        }
        var deviceID = id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw RecorderError.engineFailed("AudioUnitSetProperty returned \(status)")
        }
    }

    /// RMS mapped onto 0...1 across a 60 dB window, so the meter moves usefully
    /// at the quiet levels a back-row lecture recording actually produces.
    private static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<frames { sum += samples[frame] * samples[frame] }
        }
        let rms = sqrt(sum / Float(frames * Int(buffer.format.channelCount)))
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return max(0, min(1, (db + 60) / 60))
    }
}
