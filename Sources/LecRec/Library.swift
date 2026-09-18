import Foundation
import AVFoundation

/// One lecture as it exists on disk, assembled from whatever artifacts survived:
/// a note, a transcript, a recording, or any combination.
struct LibraryItem: Hashable {
    var course: String            // folder slug
    var courseName: String
    var date: Date
    var title: String
    var noteURL: URL?
    var transcriptURL: URL?
    var audioURL: URL?
    var duration: TimeInterval    // seconds of audio, 0 when unknown
    var wordCount: Int
    var coverage: Double?         // transcript end over audio length
    var notionURL: String?

    var hasNote: Bool { noteURL != nil }
}

/// Aggregate numbers behind the dashboard. Everything here is derived from files,
/// never stored, so deleting a lecture folder is all it takes to undo it.
struct LibraryStats {
    var lectureCount: Int = 0
    var totalDuration: TimeInterval = 0
    var totalWords: Int = 0
    var courseCount: Int = 0
    var averageCoverage: Double?
    var longest: LibraryItem?
    var firstDate: Date?
    var lastDate: Date?

    var totalHours: Double { totalDuration / 3600 }

    /// Days between the first and most recent lecture, inclusive.
    var spanDays: Int {
        guard let first = firstDate, let last = lastDate else { return 0 }
        return max(1, Calendar.current.dateComponents([.day], from: first, to: last).day.map { $0 + 1 } ?? 1)
    }
}

enum Library {
    /// Walks the notes root and rebuilds the picture from scratch.
    static func scan(settings: Settings) -> [LibraryItem] {
        let root = URL(fileURLWithPath: settings.notesRoot)
        let manager = FileManager.default
        guard let courseDirs = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }

        var items: [LibraryItem] = []
        for courseDir in courseDirs {
            guard (try? courseDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            let slug = courseDir.lastPathComponent
            guard !slug.hasPrefix(".") else { continue }
            let courseName = settings.courses.first { $0.slug == slug }?.name ?? slug

            // Group every artifact by the yyyy-MM-dd prefix that names the lecture.
            var byDate: [String: LibraryItem] = [:]

            func touch(_ stamp: String, _ mutate: (inout LibraryItem) -> Void) {
                var item = byDate[stamp] ?? LibraryItem(
                    course: slug, courseName: courseName,
                    date: parseDate(stamp) ?? Date.distantPast,
                    title: "", duration: 0, wordCount: 0)
                mutate(&item)
                byDate[stamp] = item
            }

            for note in files(in: courseDir, ext: "md") {
                guard let stamp = datePrefix(of: note) else { continue }
                let text = (try? String(contentsOf: note, encoding: .utf8)) ?? ""
                touch(stamp) {
                    $0.noteURL = note
                    $0.wordCount = text.split(whereSeparator: { $0 == " " || $0.isNewline }).count
                    $0.title = title(from: text, fallback: note.deletingPathExtension().lastPathComponent, stamp: stamp)
                    $0.notionURL = notionLink(in: text)
                }
            }
            for srt in files(in: courseDir.appendingPathComponent("transcripts"), ext: "srt") {
                guard let stamp = datePrefix(of: srt) else { continue }
                touch(stamp) { $0.transcriptURL = srt }
            }
            for audio in files(in: courseDir.appendingPathComponent("audio"), ext: nil) {
                guard let stamp = datePrefix(of: audio),
                      ["caf", "wav", "m4a", "mp3"].contains(audio.pathExtension.lowercased())
                else { continue }
                // Prefer the original over the cleaned copy for duration.
                touch(stamp) {
                    if $0.audioURL == nil || audio.lastPathComponent.contains("raw") {
                        $0.audioURL = audio
                    }
                }
            }

            for (_, var item) in byDate {
                if let audio = item.audioURL { item.duration = duration(of: audio) }
                if let srt = item.transcriptURL, item.duration > 0,
                   let end = SRT.lastTimestamp(of: srt) {
                    item.coverage = min(1, end / item.duration)
                }
                if item.title.isEmpty {
                    item.title = item.hasNote ? "Untitled lecture" : "Recording"
                }
                items.append(item)
            }
        }
        return items.sorted { $0.date > $1.date }
    }

    static func stats(for items: [LibraryItem]) -> LibraryStats {
        var stats = LibraryStats()
        stats.lectureCount = items.count
        stats.totalDuration = items.reduce(0) { $0 + $1.duration }
        stats.totalWords = items.reduce(0) { $0 + $1.wordCount }
        stats.courseCount = Set(items.map(\.course)).count
        let coverages = items.compactMap(\.coverage)
        stats.averageCoverage = coverages.isEmpty ? nil : coverages.reduce(0, +) / Double(coverages.count)
        stats.longest = items.max { $0.duration < $1.duration }
        let dates = items.map(\.date).filter { $0 > .distantPast }
        stats.firstDate = dates.min()
        stats.lastDate = dates.max()
        return stats
    }

    /// One line worth reading, chosen from whatever the data actually supports.
    /// Returns nil rather than inventing a fact when there is nothing to say.
    static func highlight(items: [LibraryItem], stats: LibraryStats) -> String? {
        guard stats.lectureCount > 0 else { return nil }
        var candidates: [String] = []

        if stats.totalDuration >= 3600 {
            candidates.append(String(format: "You have captured %.1f hours of lectures.", stats.totalHours))
        }
        if stats.totalWords >= 500 {
            let pages = max(1, stats.totalWords / 500)
            candidates.append("Your notes come to \(formatted(stats.totalWords)) words, about \(pages) pages.")
        }
        if let longest = stats.longest, longest.duration >= 600 {
            candidates.append("Your longest recording is \(longest.title) at \(clock(longest.duration)).")
        }
        if let coverage = stats.averageCoverage {
            let pct = Int((coverage * 100).rounded())
            candidates.append(pct >= 95
                ? "Transcripts are covering \(pct)% of your recordings, which is healthy."
                : "Transcripts average \(pct)% coverage. Below 95% usually means the recording started late.")
        }
        if stats.courseCount > 1 {
            candidates.append("You are tracking \(stats.courseCount) courses across \(stats.lectureCount) lectures.")
        }
        let missingNotes = items.filter { !$0.hasNote }.count
        if missingNotes > 0 {
            candidates.append("\(missingNotes) recording\(missingNotes == 1 ? "" : "s") \(missingNotes == 1 ? "has" : "have") no note yet.")
        }
        // Rotate by day so the dashboard is not identical every time it opens.
        guard !candidates.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return candidates[day % candidates.count]
    }

    // MARK: - Helpers

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 { return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60) }
        return String(format: "%dm %02ds", total / 60, total % 60)
    }

    static func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func files(in directory: URL, ext: String?) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let ext else { return contents }
        return contents.filter { $0.pathExtension.lowercased() == ext }
    }

    private static func datePrefix(of url: URL) -> String? {
        let name = url.lastPathComponent
        guard name.count >= 10 else { return nil }
        let stamp = String(name.prefix(10))
        return parseDate(stamp) == nil ? nil : stamp
    }

    private static func parseDate(_ stamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: stamp)
    }

    /// Prefers the note's H1, falling back to the filename slug.
    private static func title(from text: String, fallback: String, stamp: String) -> String {
        if let heading = text.components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("# ") }) {
            var trimmed = heading.dropFirst(2).trimmingCharacters(in: .whitespaces)
            // Notes are titled "IR — Search Engine Architecture"; keep the topic.
            for separator in [" - ", ": "] {
                if let range = trimmed.range(of: separator) {
                    trimmed = String(trimmed[range.upperBound...])
                    break
                }
            }
            if !trimmed.isEmpty { return trimmed }
        }
        return fallback.replacingOccurrences(of: stamp + "-", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private static func notionLink(in text: String) -> String? {
        guard let range = text.range(of: #"https://[^\s\)]*notion\.[^\s\)]*"#, options: .regularExpression)
        else { return nil }
        return String(text[range])
    }

    private static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let rate = file.fileFormat.sampleRate
        return rate > 0 ? Double(file.length) / rate : 0
    }
}
