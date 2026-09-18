import Foundation

/// A course the user records. `slug` names the folder under the notes root.
struct Course: Codable, Hashable, Identifiable {
    var id: String { slug }
    var slug: String        // "NLP"
    var name: String        // "NLP CS 6120"
    var notionCourse: String // must match a Notion select option: "NLP"

    static let defaults: [Course] = [
        Course(slug: "NLP", name: "NLP CS 6120", notionCourse: "NLP"),
        Course(slug: "IR", name: "IR CS 6200", notionCourse: "Information Retrieval"),
    ]
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
    var selectedCourseSlug: String = "NLP"
    var inputDeviceUID: String? = nil      // nil means system default input
    var destination: Destination = .notion
    var obsidianVaultPath: String = ""
    var appleNotesFolder: String = "Course Notes"
    var notesRoot: String = NSString(string: "~/Documents/course-notes").expandingTildeInPath
    var claudeModel: String = "opus"
    var denoise: Bool = true
    var autoRunPipelineOnStop: Bool = true

    /// Read the course's recent notes before writing, so each lecture is placed in
    /// the arc of the course instead of standing alone.
    var linkPreviousLectures: Bool = true
    /// How many earlier lectures to pull in. Four covers about two weeks.
    var continuityLookback: Int = 4
    /// Allow editing an earlier published note to tick off a gap this lecture
    /// answered. Off by default because it writes to already-published pages.
    var closeResolvedGaps: Bool = false

    var selectedCourse: Course {
        courses.first { $0.slug == selectedCourseSlug } ?? courses[0]
    }

    // MARK: - Persistence

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lectern", isDirectory: true)
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
