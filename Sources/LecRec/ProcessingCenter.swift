import Foundation

/// Owns pipeline runs for the whole app.
///
/// Both the menu bar popover and the dashboard can start processing, and a
/// transcription pass is expensive, so exactly one run is allowed at a time and
/// both surfaces observe the same state rather than each holding their own.
final class ProcessingCenter {
    static let shared = ProcessingCenter()

    struct Progress {
        var stage: PipelineStage
        var detail: String
        var fraction: Double        // 0...1
        var lecture: Lecture
    }

    private(set) var current: Progress?
    var isRunning: Bool { current != nil }

    /// Observers are keyed so a rebuilt view can replace its own registration.
    private var observers: [String: (Progress?) -> Void] = [:]
    private var completions: [String: (Result<URL, Error>, Lecture) -> Void] = [:]

    func observe(_ key: String, _ handler: @escaping (Progress?) -> Void) {
        observers[key] = handler
        handler(current)
    }

    func onComplete(_ key: String, _ handler: @escaping (Result<URL, Error>, Lecture) -> Void) {
        completions[key] = handler
    }

    /// Fractions are stage weights, not measured work. Transcription dominates a
    /// real lecture, so it gets the widest band and creeps while it runs.
    private static func band(for stage: PipelineStage) -> (start: Double, end: Double) {
        switch stage {
        // Phase one ends at the pause; phase two resumes from there.
        case .cleaning:     return (0.02, 0.15)
        case .transcribing: return (0.15, 0.68)
        case .checking:     return (0.68, 0.72)
        case .awaitingDeck: return (0.72, 0.72)
        case .recalling:    return (0.72, 0.78)
        case .reasoning:    return (0.78, 0.94)
        case .publishing:   return (0.94, 0.99)
        case .done:         return (1.00, 1.00)
        default:            return (0.0, 0.0)
        }
    }

    enum StartError: LocalizedError {
        case busy
        var errorDescription: String? {
            "LecRec is already processing a lecture. Wait for it to finish."
        }
    }

    /// Phase one. Ends by parking the lecture in the pending queue rather than
    /// carrying straight on to the write-up.
    @discardableResult
    func startTranscription(lecture: Lecture, settings: Settings) throws -> Bool {
        guard !isRunning else { throw StartError.busy }
        let pipeline = makePipeline(settings: settings, lecture: lecture)
        publish(Progress(stage: .cleaning, detail: "Starting", fraction: 0.02, lecture: lecture))

        Task { @MainActor in
            do {
                let pending = try await pipeline.transcribe(lecture: lecture)
                self.creepTimer?.invalidate()
                PendingStore.add(pending)
                self.current = nil
                self.publish(Progress(stage: .awaitingDeck,
                                      detail: "Attach your slide deck, then start the write-up",
                                      fraction: 0.72, lecture: lecture))
                self.current = nil
                self.notifyPending(pending)
                self.observers.values.forEach { $0(nil) }
            } catch {
                self.creepTimer?.invalidate()
                self.finish(.failure(error), lecture: lecture)
            }
        }
        return true
    }

    /// Phase two, started from the UI once the user has decided about the deck.
    @discardableResult
    func startWriteUp(_ pending: PendingLecture, settings: Settings) throws -> Bool {
        guard !isRunning else { throw StartError.busy }
        let lecture = pending.lecture
        let pipeline = makePipeline(settings: settings, lecture: lecture)
        publish(Progress(stage: .recalling, detail: "Starting the write-up",
                         fraction: 0.72, lecture: lecture))

        Task { @MainActor in
            do {
                let note = try await pipeline.writeUp(pending)
                self.creepTimer?.invalidate()
                PendingStore.remove(pending)
                self.publish(Progress(stage: .done, detail: "Published", fraction: 1, lecture: lecture))
                self.finish(.success(note), lecture: lecture)
            } catch {
                self.creepTimer?.invalidate()
                self.finish(.failure(error), lecture: lecture)
            }
        }
        return true
    }

    private var creepTimer: Timer?

    private func makePipeline(settings: Settings, lecture: Lecture) -> Pipeline {
        let pipeline = Pipeline(settings: settings)
        pipeline.onStage = { [weak self] stage, detail in
            guard let self else { return }
            self.creepTimer?.invalidate()
            let band = Self.band(for: stage)
            self.publish(Progress(stage: stage, detail: detail,
                                  fraction: band.start, lecture: lecture))
            let span = band.end - band.start
            guard span > 0.05 else { return }
            var elapsed: Double = 0
            let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self, let current = self.current, current.stage == stage else { return }
                elapsed += 2
                let progress = 1 - exp(-elapsed / 240)
                self.publish(Progress(stage: stage, detail: current.detail,
                                      fraction: band.start + span * progress * 0.95,
                                      lecture: lecture))
            }
            RunLoop.main.add(timer, forMode: .common)
            self.creepTimer = timer
        }
        pipeline.onLog = { Diagnostics.log($0) }
        return pipeline
    }

    /// The whole point of pausing is that the user is not watching, so tell them.
    private func notifyPending(_ pending: PendingLecture) {
        Notifier.post(
            title: "\(pending.courseName) is transcribed",
            body: "\(pending.coverageText). Attach your slide deck in LecRec, then start the write-up.")
    }

    private func publish(_ progress: Progress) {
        current = progress
        let snapshot = observers.values
        DispatchQueue.main.async { snapshot.forEach { $0(progress) } }
    }

    private func finish(_ result: Result<URL, Error>, lecture: Lecture) {
        current = nil
        let handlers = completions.values
        let observing = observers.values
        DispatchQueue.main.async {
            handlers.forEach { $0(result, lecture) }
            observing.forEach { $0(nil) }
            switch result {
            case .success(let note):
                Notifier.post(
                    title: "\(lecture.course.name) note is ready",
                    body: "\(note.lastPathComponent) was published to your notes.")
            case .failure(let error):
                Notifier.post(
                    title: "Processing failed",
                    body: "Your recording is safe. \(error.localizedDescription)")
            }
        }
    }
}
