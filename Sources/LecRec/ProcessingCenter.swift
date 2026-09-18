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
        case .cleaning:     return (0.02, 0.12)
        case .transcribing: return (0.12, 0.58)
        case .checking:     return (0.58, 0.62)
        case .recalling:    return (0.62, 0.70)
        case .reasoning:    return (0.70, 0.93)
        case .publishing:   return (0.93, 0.99)
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

    @discardableResult
    func start(lecture: Lecture, settings: Settings) throws -> Bool {
        guard !isRunning else { throw StartError.busy }

        let pipeline = Pipeline(settings: settings)
        var creepTimer: Timer?

        publish(Progress(stage: .cleaning, detail: "Starting", fraction: 0.02, lecture: lecture))

        pipeline.onStage = { [weak self] stage, detail in
            guard let self else { return }
            creepTimer?.invalidate()
            let band = Self.band(for: stage)
            self.publish(Progress(stage: stage, detail: detail,
                                  fraction: band.start, lecture: lecture))

            // Long stages report nothing until they finish, so inch forward to
            // show the app is alive without ever claiming to be done.
            let span = band.end - band.start
            guard span > 0.05 else { return }
            var elapsed: Double = 0
            let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self, let current = self.current, current.stage == stage else { return }
                elapsed += 2
                // Asymptotic: approaches the band end without reaching it.
                let progress = 1 - exp(-elapsed / 90)
                self.publish(Progress(stage: stage, detail: current.detail,
                                      fraction: band.start + span * progress * 0.95,
                                      lecture: lecture))
            }
            RunLoop.main.add(timer, forMode: .common)
            creepTimer = timer
        }
        pipeline.onLog = { Diagnostics.log($0) }

        Task { @MainActor in
            do {
                let note = try await pipeline.run(lecture: lecture)
                creepTimer?.invalidate()
                self.publish(Progress(stage: .done, detail: "Published", fraction: 1, lecture: lecture))
                self.finish(.success(note), lecture: lecture)
            } catch {
                creepTimer?.invalidate()
                self.finish(.failure(error), lecture: lecture)
            }
        }
        return true
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
