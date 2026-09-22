import Foundation

/// A lecture that has been recorded and transcribed but not yet written up.
///
/// The pipeline stops here on purpose. The slide deck is the source that turns a
/// transcript-only note into a cross-checked one, and it usually is not to hand
/// the moment class ends. Pausing before the expensive step means the deck can
/// still be attached, rather than arriving after the note is already published.
///
/// Persisted, so quitting the app does not lose a transcribed lecture.
struct PendingLecture: Codable, Hashable {
    var courseSlug: String
    var courseName: String
    var notionCourse: String
    var date: Date
    var slug: String
    var audioPath: String
    var transcriptPath: String
    var audioDuration: TimeInterval
    var coverage: Double?
    var deckPath: String?
    var transcribedAt: Date

    var transcriptURL: URL { URL(fileURLWithPath: transcriptPath) }
    var audioURL: URL { URL(fileURLWithPath: audioPath) }

    var dateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var coverageText: String {
        guard let coverage else { return "coverage unknown" }
        let pct = Int((coverage * 100).rounded())
        return pct >= 95 ? "\(pct)% covered" : "only \(pct)% covered"
    }

    var lecture: Lecture {
        Lecture(course: Course(slug: courseSlug, name: courseName, notionCourse: notionCourse),
                date: date, slug: slug,
                audioURL: audioURL, audioDuration: audioDuration,
                deckPath: deckPath)
    }
}

/// The queue of transcribed lectures waiting for a deck and a go-ahead.
enum PendingStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LecRec", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("pending.json")
    }

    static func load() -> [PendingLecture] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([PendingLecture].self, from: data)
        else { return [] }
        // Drop anything whose transcript has gone, so the queue cannot rot.
        return items.filter { FileManager.default.fileExists(atPath: $0.transcriptPath) }
    }

    static func save(_ items: [PendingLecture]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func add(_ item: PendingLecture) {
        var items = load().filter { !($0.courseSlug == item.courseSlug && $0.dateStamp == item.dateStamp) }
        items.append(item)
        save(items)
        Diagnostics.log("pending: queued \(item.courseName) \(item.dateStamp) for write-up")
    }

    static func update(_ item: PendingLecture) {
        var items = load()
        guard let index = items.firstIndex(where: {
            $0.courseSlug == item.courseSlug && $0.dateStamp == item.dateStamp
        }) else { return add(item) }
        items[index] = item
        save(items)
    }

    static func remove(_ item: PendingLecture) {
        save(load().filter { !($0.courseSlug == item.courseSlug && $0.dateStamp == item.dateStamp) })
        Diagnostics.log("pending: cleared \(item.courseName) \(item.dateStamp)")
    }

    static var first: PendingLecture? { load().sorted { $0.transcribedAt > $1.transcribedAt }.first }
}
