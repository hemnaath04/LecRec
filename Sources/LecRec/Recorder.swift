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
        case notEnoughDisk(free: Int64, minutes: Int)

        var errorDescription: String? {
            switch self {
            case .micDenied:
                return "Microphone access was denied. Grant it in System Settings, Privacy and Security, Microphone."
            case .deviceUnavailable(let name):
                return "Input device \(name) is unavailable."
            case .engineFailed(let detail):
                return "Could not start the audio engine: \(detail)"
            case .notEnoughDisk(let free, let minutes):
                return "Only \(DiskSpace.formatted(free)) left on disk, about \(minutes) minutes of recording. "
                    + "Free up space before starting, because a full disk stops a recording with no warning."
            }
        }
    }

    /// Fires on the main queue roughly 10x a second while recording.
    var onLevel: ((Float) -> Void)?
    /// Fires on the main queue once a second with elapsed seconds.
    var onTick: ((TimeInterval) -> Void)?

    /// Recreated for every recording. A reused engine keeps its input
    /// AudioUnit bound to whichever HAL device it saw first, and once that
    /// binding goes stale a later start() on an explicit device fails with
    /// kAudioHardwareNotRunningError ('stop'), which is what stopped the user
    /// recording an IR lecture on 2026-09-29. A fresh engine has no stale state.
    private var engine = AVAudioEngine()
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
    /// The device actually feeding the tap, which is not always the one that was
    /// requested. Today a recording ran on the built-in mic while the setting
    /// said system default, and nothing on screen said so.
    private(set) var activeDeviceName: String = "unknown"

    var bytesWritten: Int64 {
        guard let url = outputURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Frames written so far, the authoritative duration source for the coverage check.
    private var framesWritten: AVAudioFramePosition = 0
    private var sampleRate: Double = 48_000

    var duration: TimeInterval {
        sampleRate > 0 ? Double(framesWritten) / sampleRate : 0
    }

    // MARK: - Dead input

    /// A Continuity microphone can stop delivering audio without ever leaving
    /// CoreAudio. The device stays present, the engine stays running, and every
    /// buffer arrives full of zeros, so AVAudioEngineConfigurationChange never
    /// fires and the dropout recovery below it never runs. On 2026-09-25 that
    /// silently cost 45 of 81 recorded minutes. The only reliable signal is the
    /// sample data itself, so the tap watches for it.
    private var silentFrames: AVAudioFramePosition = 0
    private var lastDeadRecovery: Date?
    /// Cumulative frames of pure digital silence, for the quality gate.
    private(set) var deadFrames: AVAudioFramePosition = 0

    /// Seconds of continuous all-zero input before the input counts as dead.
    /// Long enough that a genuinely silent room never trips it, short enough
    /// that a lecture loses a sentence rather than half an hour.
    private static let deadInputThreshold: TimeInterval = 15

    /// Fires on the main queue when the input goes dead, and again when it recovers.
    var onInputDead: ((Bool) -> Void)?

    /// Disk is getting tight but the recording continues.
    var onDiskWarning: ((String) -> Void)?
    /// Disk is nearly gone, so the recording is being ended deliberately while
    /// the file can still be closed properly. Better a short lecture that plays
    /// than a long one truncated mid-write.
    var onDiskCritical: ((String) -> Void)?

    /// Fraction of the recording that carried actual samples, 0...1.
    var signalCoverage: Double {
        guard framesWritten > 0 else { return 0 }
        return Double(framesWritten - deadFrames) / Double(framesWritten)
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

    /// Never let a bad microphone choice mean no recording at all. A lecture
    /// happens once, so a failure on the chosen device falls back to the system
    /// default and says so, rather than leaving the user with nothing.
    func start(deviceUID: String?, to url: URL) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.micDenied
        }
        do {
            try startEngine(deviceUID: deviceUID, to: url)
        } catch {
            guard deviceUID != nil else { throw error }
            Diagnostics.log("start failed on the requested device: \(error.localizedDescription)")
            Diagnostics.log("retrying on the system default input")
            try startEngine(deviceUID: nil, to: url)
            onInputChanged?("Could not use the chosen microphone, recording on \(activeDeviceName) instead.")
        }
    }

    private func startEngine(deviceUID: String?, to url: URL) throws {
        resetEngine()

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

        // 16-bit mono at the device rate. Checked before the file is created,
        // so a doomed recording never starts at all.
        bytesPerSecond = format.sampleRate * Double(format.channelCount) * 2
        if let free = DiskSpace.availableBytes(at: url) {
            let needed = Int64(bytesPerSecond * DiskSpace.plannedSeconds) + DiskSpace.reserveBytes
            if free < needed {
                let minutes = DiskSpace.minutes(ofRoom: free - DiskSpace.reserveBytes,
                                                bytesPerSecond: bytesPerSecond)
                Diagnostics.log("disk check failed: \(DiskSpace.formatted(free)) free, "
                    + "needs \(DiskSpace.formatted(needed)) for a full lecture")
                throw RecorderError.notEnoughDisk(free: free, minutes: max(0, minutes))
            }
            Diagnostics.log("disk: \(DiskSpace.formatted(free)) free, "
                + "room for about \(DiskSpace.minutes(ofRoom: free, bytesPerSecond: bytesPerSecond)) minutes")
        }

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
            self.noteInputActivity(level: level, frames: buffer.frameLength)
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
        let resolved = deviceUID.flatMap { AudioDevices.device(uid: $0) } ?? AudioDevices.defaultInput()
        activeDeviceName = resolved?.name ?? "unknown input"
        Diagnostics.log("recording input: \(activeDeviceName) at \(Int(engine.inputNode.inputFormat(forBus: 0).sampleRate)) Hz")
        observeConfigurationChanges()

        startedAt = Date()
        isRecording = true
        Shell.yieldToRecording = true
        lastHeartbeatMinute = -1
        peakSinceHeartbeat = 0
        lastFrameCount = 0
        stalledSeconds = 0
        warnedAboutDisk = false
        silentFrames = 0
        deadFrames = 0
        lastDeadRecovery = nil
        let tick = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            self.onTick?(elapsed)
            self.checkForStall()
            self.heartbeat(elapsed: elapsed)
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// Tear the engine down and build a new one, so nothing carries over from a
    /// previous recording or a failed attempt.
    private func resetEngine() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine.reset()
        engine = AVAudioEngine()
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

    /// Stop on purpose before the disk runs out.
    ///
    /// A writer that dies on a full volume leaves a file whose header was never
    /// finalised and loses everything still buffered. Ending the recording
    /// deliberately keeps what was captured and tells the user why.
    private func checkDiskSpace() {
        guard isRecording, let url = outputURL,
              let free = DiskSpace.availableBytes(at: url) else { return }

        if free < DiskSpace.criticalBytes {
            let message = "Recording stopped: only \(DiskSpace.formatted(free)) left on disk. "
                + "What was captured so far has been saved."
            Diagnostics.log("DISK CRITICAL: \(DiskSpace.formatted(free)) free, ending the recording")
            onDiskCritical?(message)
            return
        }

        guard free < DiskSpace.warningBytes, !warnedAboutDisk else { return }
        warnedAboutDisk = true
        let minutes = DiskSpace.minutes(ofRoom: free - DiskSpace.criticalBytes,
                                        bytesPerSecond: bytesPerSecond)
        let message = "Disk is nearly full: \(DiskSpace.formatted(free)) left, "
            + "about \(max(0, minutes)) more minutes of recording."
        Diagnostics.log("DISK LOW: \(message)")
        onDiskWarning?(message)
    }

    /// Catch a tap that has stopped firing altogether.
    ///
    /// noteInputActivity and SilenceWatchdog are both driven by the tap, so
    /// neither can see the tap itself die: no buffers means no callbacks means
    /// no detection. On 2026-10-02 the tap delivered 1.4 seconds and stopped,
    /// and the recording sat at 0 MB for four minutes reporting healthily.
    /// This check runs on the 1 Hz timer, which is independent of the audio
    /// thread, and compares the frame count against the previous second.
    private func checkForStall() {
        guard isRecording else { return }
        guard framesWritten == lastFrameCount else {
            if stalledSeconds >= Recorder.stallThreshold {
                Diagnostics.log("input resumed after a stall")
                DispatchQueue.main.async { self.onInputDead?(false) }
            }
            stalledSeconds = 0
            lastFrameCount = framesWritten
            return
        }

        stalledSeconds += 1
        guard stalledSeconds == Recorder.stallThreshold else { return }
        if let last = lastDeadRecovery, Date().timeIntervalSince(last) < 60 { return }
        lastDeadRecovery = Date()
        Diagnostics.log("INPUT STALLED: no audio buffers for \(stalledSeconds)s from \(activeDeviceName), restarting engine")
        onInputDead?(true)
        handleConfigurationChange()
    }

    /// Seconds without a single new frame before the tap counts as stalled.
    private static let stallThreshold = 10
    private var lastFrameCount: AVAudioFramePosition = 0
    private var stalledSeconds = 0
    private var bytesPerSecond: Double = 96_000
    private var warnedAboutDisk = false

    /// Once a minute, say what the recording is actually doing.
    ///
    /// The log had one line when a recording started and one when it stopped,
    /// and on 2026-09-25 that left 111 minutes of nothing between them while the
    /// microphone quietly died twice. A recording that narrates itself turns the
    /// next outage into a log line instead of a forensic audio analysis.
    private func heartbeat(elapsed: TimeInterval) {
        // Deliberately not `Int(elapsed) % 60 == 0`: a 1 Hz Timer drifts, so
        // elapsed can step 59 -> 61 and that minute's line never gets written.
        // Comparing whole minutes fires once per minute whatever the drift.
        let minute = Int(elapsed) / 60
        guard minute > 0, minute != lastHeartbeatMinute else { return }
        lastHeartbeatMinute = minute
        let megabytes = Double(bytesWritten) / 1_048_576
        let deadSeconds = Double(deadFrames) / sampleRate
        let peak = peakSinceHeartbeat
        peakSinceHeartbeat = 0
        let free = outputURL.flatMap { DiskSpace.availableBytes(at: $0) }
        let room = free.map { ", \(DiskSpace.formatted($0)) disk free" } ?? ""
        Diagnostics.log(String(
            format: "recording %dm: %.0f MB, peak level %.2f, %.0f%% signal, %.0fs dead, on %@%@",
            minute, megabytes, peak, signalCoverage * 100, deadSeconds, activeDeviceName, room))
        checkDiskSpace()
    }

    private var lastHeartbeatMinute = -1
    private var peakSinceHeartbeat: Float = 0

    /// Called from the tap on the audio thread for every buffer. A level of
    /// exactly zero means every sample in the buffer was zero, which real
    /// microphones do not produce even in a silent room: there is always a
    /// noise floor. Sustained zeros mean the device has stopped feeding us.
    private func noteInputActivity(level: Float, frames: AVAudioFrameCount) {
        peakSinceHeartbeat = max(peakSinceHeartbeat, level)
        guard level == 0 else {
            if silentFrames > 0 {
                let recovered = silentFrames >= deadThresholdFrames
                silentFrames = 0
                if recovered {
                    Diagnostics.log("input recovered, audio is flowing again")
                    DispatchQueue.main.async { self.onInputDead?(false) }
                }
            }
            return
        }

        silentFrames += AVAudioFramePosition(frames)
        deadFrames += AVAudioFramePosition(frames)

        guard silentFrames >= deadThresholdFrames else { return }
        // Only act once per outage, and never more than once a minute, so a
        // genuinely dead device does not spin the engine in a restart loop.
        if let last = lastDeadRecovery, Date().timeIntervalSince(last) < 60 { return }
        lastDeadRecovery = Date()
        let seconds = Double(silentFrames) / sampleRate
        Diagnostics.log("INPUT DEAD: \(Int(seconds))s of all-zero samples from \(activeDeviceName), restarting engine")
        DispatchQueue.main.async {
            self.onInputDead?(true)
            self.handleConfigurationChange()
        }
    }

    private var deadThresholdFrames: AVAudioFramePosition {
        AVAudioFramePosition(Recorder.deadInputThreshold * sampleRate)
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
        activeDeviceName = name

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
            self.noteInputActivity(level: level, frames: buffer.frameLength)
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
        Shell.yieldToRecording = false
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
