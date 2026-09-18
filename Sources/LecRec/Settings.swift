import Foundation

/// A course the user records. `slug` names the folder under the notes root.
struct Course: Codable, Hashable, Identifiable {
    var id: String { slug }
    var slug: String        // "NLP"
    var name: String        // "NLP CS 6120"
    var notionCourse: String // must match a Notion select option: "NLP"

    /// Empty on a fresh install. Onboarding asks for the user's own courses.
    static let defaults: [Course] = []

    /// Builds a course from whatever the user typed, deriving a safe folder slug.
    init(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed
        self.notionCourse = trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
        let cleaned = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        let parts = cleaned.split(whereSeparator: { $0 == " " || $0 == "-" })
        self.slug = parts.isEmpty ? "course" : parts.joined(separator: "-")
    }

    init(slug: String, name: String, notionCourse: String) {
        self.slug = slug
        self.name = name
        self.notionCourse = notionCourse
    }
}

enum Destination: String, Codable, CaseIterable {
    case markdown
    case notion
    case appleNotes
    case obsidian

    var label: String {
        switch self {
        case .markdown: return "Local Markdown only"
        case .notion: return "Notion"
        case .appleNotes: return "Apple Notes"
        case .obsidian: return "Obsidian vault"
        }
    }

    /// MCP servers this destination needs. Empty means no network tools at all.
    var requiredMCPServers: [String] {
        switch self {
        case .notion: return ["notion"]
        case .markdown, .appleNotes, .obsidian: return []
        }
    }

    /// True when the destination can be reached without extra setup in Settings.
    var needsPath: Bool { self == .obsidian }
}

struct Settings: Codable {
    var courses: [Course] = Course.defaults
    var selectedCourseSlug: String = ""
    var inputDeviceUID: String? = nil      // nil means system default input
    var destination: Destination = .notion
    var obsidianVaultPath: String = ""
    var appleNotesFolder: String = "Course Notes"
    var notesRoot: String = NSString(string: "~/Documents/course-notes").expandingTildeInPath
    var claudeModel: String = "opus"
    var denoise: Bool = true
    var transcriptionModel: TranscriptionModel = TranscriptionModel.recommended
    var autoRunPipelineOnStop: Bool = true

    /// Read the course's recent notes before writing, so each lecture is placed in
    /// the arc of the course instead of standing alone.
    var linkPreviousLectures: Bool = true
    /// How many earlier lectures to pull in. Four covers about two weeks.
    var continuityLookback: Int = 4
    /// Allow editing an earlier published note to tick off a gap this lecture
    /// answered. Off by default because it writes to already-published pages.
    var closeResolvedGaps: Bool = false

    // MARK: - Per install identity
    //
    // These are discovered during onboarding, never hardcoded. The whole reason
    // this app could not be shared before is that the notes database belonged to
    // one person.

    /// Notion data source that receives lecture notes, for this user's workspace.
    var notionDataSourceID: String = ""
    /// Page the database lives under, kept for the onboarding summary.
    var notionParentPageID: String = ""
    var notionDatabaseURL: String = ""
    var hasCompletedOnboarding: Bool = false

    var selectedCourse: Course? {
        courses.first { $0.slug == selectedCourseSlug } ?? courses.first
    }

    /// Onboarding is done when the app has everything it needs to run unattended.
    var isReadyToRecord: Bool {
        guard !courses.isEmpty else { return false }
        if destination == .notion { return !notionDataSourceID.isEmpty }
        if destination == .obsidian { return !obsidianVaultPath.isEmpty }
        return true
    }

    // MARK: - Decoding
    //
    // Synthesised Codable throws when a key is absent, even for a property with a
    // default, so shipping any new setting would have made every existing install
    // fall back to an empty Settings and rerun onboarding. Every field is decoded
    // permissively instead, which is what makes updates safe.

    init() {}

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? box.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        let defaults = Settings()
        courses = value(.courses, defaults.courses)
        selectedCourseSlug = value(.selectedCourseSlug, defaults.selectedCourseSlug)
        inputDeviceUID = value(.inputDeviceUID, defaults.inputDeviceUID)
        destination = value(.destination, defaults.destination)
        obsidianVaultPath = value(.obsidianVaultPath, defaults.obsidianVaultPath)
        appleNotesFolder = value(.appleNotesFolder, defaults.appleNotesFolder)
        notesRoot = value(.notesRoot, defaults.notesRoot)
        claudeModel = value(.claudeModel, defaults.claudeModel)
        denoise = value(.denoise, defaults.denoise)
        transcriptionModel = value(.transcriptionModel, defaults.transcriptionModel)
        autoRunPipelineOnStop = value(.autoRunPipelineOnStop, defaults.autoRunPipelineOnStop)
        linkPreviousLectures = value(.linkPreviousLectures, defaults.linkPreviousLectures)
        continuityLookback = value(.continuityLookback, defaults.continuityLookback)
        closeResolvedGaps = value(.closeResolvedGaps, defaults.closeResolvedGaps)
        notionDataSourceID = value(.notionDataSourceID, defaults.notionDataSourceID)
        notionParentPageID = value(.notionParentPageID, defaults.notionParentPageID)
        notionDatabaseURL = value(.notionDatabaseURL, defaults.notionDatabaseURL)
        hasCompletedOnboarding = value(.hasCompletedOnboarding, defaults.hasCompletedOnboarding)

        // A model the machine cannot run is worse than no preference at all.
        if !TranscriptionModel.available.contains(transcriptionModel) {
            transcriptionModel = .recommended
        }
    }

    // MARK: - Persistence

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LecRec", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("settings.json")
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Settings.fileURL, options: .atomic)
    }

    /// Directory for one lecture's artifacts: audio, transcript, note.
    func lectureDirectory(course: Course, date: Date) -> URL {
        URL(fileURLWithPath: notesRoot)
            .appendingPathComponent(course.slug, isDirectory: true)
    }
}
