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
    private var configObserver: NSObjectProtocol?
    private var requestedDeviceUID: String?
    private var currentDestination: URL?
    /// Extra files written after a mid-lecture device change, in order.
    private(set) var continuationFiles: [URL] = []

    /// Fires when the input device disappears mid-recording, which is the
    /// realistic failure for a Continuity microphone: the phone locks, wanders
    /// out of range, or takes a call.
    var onInputChanged: ((String) -> Void)?
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
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Diagnostics.log("microphone authorization status = \(describe(status))")
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            Diagnostics.log("microphone prompt answered: \(granted ? "granted" : "denied")")
            return granted
        default:
            Diagnostics.log("microphone blocked, status \(describe(status))")
            return false
        }
    }

    /// Triggered once at launch. Until an app actually asks, macOS does not list
    /// it under Privacy and Security, Microphone, and there is no way to add it
    /// by hand: there is no plus button on that pane. An app that never asks is
    /// therefore impossible for the user to authorise, which is what happened.
    static func primePermissionIfNeeded() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else {
            Diagnostics.log("microphone already decided: "
                + describe(AVCaptureDevice.authorizationStatus(for: .audio)))
            return
        }
        Diagnostics.log("microphone undecided at launch, asking now so the app is listed")
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Diagnostics.log("launch microphone prompt: \(granted ? "granted" : "denied")")
        }
    }

    static func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
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
            // 16-bit halves the on-disk rate during a lecture, from about
            // 11.5 MB/min to 5.8, with nothing lost for a room microphone.
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let audioFile = try AVAudioFile(forWriting: url, settings: settings,
                                        commonFormat: .pcmFormatFloat32, interleaved: false)
        // commonFormat stays float32: that is the tap's format, and AVAudioFile
        // converts to the 16-bit file format on write.
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

        requestedDeviceUID = deviceUID
        currentDestination = url
        observeConfigurationChanges()

        startedAt = Date()
        isRecording = true
        let tick = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            self.onTick?(Date().timeIntervalSince(startedAt))
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// AVAudioEngine posts this when the input hardware changes underneath it,
    /// including when a Continuity microphone vanishes. Without handling it the
    /// engine keeps running and writes silence, which is the worst outcome:
    /// the recording looks healthy and contains nothing.
    private func observeConfigurationChanges() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main) { [weak self] _ in
                self?.handleConfigurationChange()
            }
    }

    private func handleConfigurationChange() {
        guard isRecording else { return }
        let wanted = requestedDeviceUID.flatMap { AudioDevices.device(uid: $0) }
        let stillPresent = wanted != nil
        Diagnostics.log("input configuration changed, requested device present: \(stillPresent)")

        // Close the current segment cleanly, then continue into a new one.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil

        let fallback = stillPresent ? wanted : AudioDevices.defaultInput()
        let name = fallback?.name ?? "the system default input"

        guard let destination = currentDestination else { return }
        let index = continuationFiles.count + 2
        let next = destination.deletingPathExtension()
            .appendingPathExtension("part\(index).caf")

        do {
            try startSegment(deviceID: fallback?.id, to: next)
            continuationFiles.append(next)
            onInputChanged?(stillPresent
                ? "Input reconnected, continuing on \(name)."
                : "Input was lost, continuing on \(name).")
            Diagnostics.log("continuing recording into \(next.lastPathComponent) on \(name)")
        } catch {
            Diagnostics.log("FAILED to continue after input change: \(error.localizedDescription)")
            onInputChanged?("Recording stopped: the input device was lost.")
            isRecording = false
        }
    }

    /// Opens a new file and restarts capture, used both for the first segment
    /// and for continuing after a device change.
    private func startSegment(deviceID: AudioDeviceID?, to url: URL) throws {
        if let deviceID { try setInputDevice(deviceID) }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.engineFailed("input reported \(format.sampleRate) Hz")
        }
        sampleRate = format.sampleRate

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.file?.write(from: buffer)
            self.framesWritten += AVAudioFramePosition(buffer.frameLength)
            let level = Recorder.normalizedLevel(buffer)
            DispatchQueue.main.async { self.onLevel?(level) }
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops capture and returns the finalised file plus its true duration.
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval, segments: [URL])? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }

        let result = outputURL.map { (url: $0, duration: duration, segments: continuationFiles) }
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
