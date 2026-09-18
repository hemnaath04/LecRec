import Foundation

/// Drives the installed Claude Code CLI in headless mode.
///
/// The containment strategy is structural, not just prompt wording. Four levers,
/// in descending order of how much they actually guarantee:
///   1. `--mcp-config` declares only the servers the chosen destination needs,
///      so gmail, atlassian, job-os and the rest are never loaded at all.
///   2. `--disallowedTools` hard-denies network and history-rewriting tools.
///   3. cwd plus `--add-dir` bound file access to this lecture's folders.
///   4. `--append-system-prompt` states the remaining constraints in words.
final class ClaudeRunner {
    struct NotInstalled: LocalizedError {
        var errorDescription: String? {
            "The claude CLI was not found. Install Claude Code, or check that it is on PATH."
        }
    }

    struct RunFailed: LocalizedError {
        let detail: String
        var errorDescription: String? { "Claude Code could not finish the note: \(detail)" }
    }

    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    /// Tools the run is allowed to auto-approve. Deliberately narrow: read and
    /// write notes, extract a deck, talk to the destination's MCP server.
    private var allowedTools: [String] {
        var tools = [
            "Read", "Write", "Edit", "Glob", "Grep", "Skill", "TodoWrite",
            "Bash(pdftotext:*)", "Bash(pdftoppm:*)", "Bash(python3:*)", "Bash(mkdir:*)",
        ]
        for server in settings.destination.requiredMCPServers {
            tools.append("mcp__\(server)__*")
        }
        if settings.destination == .appleNotes {
            tools.append("Bash(osascript:*)")
        }
        return tools
    }

    /// Hard denies. These hold even under `--permission-mode auto`.
    private let disallowedTools = [
        "WebFetch", "WebSearch", "Task", "Agent",
        "Bash(rm:*)", "Bash(git:*)", "Bash(curl:*)", "Bash(ssh:*)",
        "Bash(brew:*)", "Bash(npm:*)", "Bash(pip:*)", "Bash(uv:*)",
        "Bash(launchctl:*)", "Bash(defaults:*)", "Bash(sudo:*)",
    ]

    func buildNote(lecture: Lecture,
                   transcript: URL,
                   coverage: CoverageReport,
                   onLog: ((String) -> Void)?,
                   onStage: ((String) -> Void)?) async throws -> URL {
        let claude = Shell.which("claude")
            ?? NSString(string: "~/.claude/local/claude").expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: claude) else { throw NotInstalled() }

        let courseDir = URL(fileURLWithPath: settings.notesRoot)
            .appendingPathComponent(lecture.course.slug, isDirectory: true)
        let noteURL = courseDir.appendingPathComponent("\(lecture.baseName).md")

        let mcpConfig = try writeScopedMCPConfig(into: courseDir)
        let prompt = Prompt.buildNote(lecture: lecture, transcript: transcript,
                                      coverage: coverage, noteURL: noteURL,
                                      settings: settings)

        var arguments = [
            "-p", prompt,
            "--permission-mode", "auto",
            "--model", settings.claudeModel,
            "--output-format", "stream-json",
            "--verbose",
            "--mcp-config", mcpConfig.path,
            "--append-system-prompt", Prompt.systemConstraints(settings: settings),
            "--allowedTools",
        ] + allowedTools + ["--disallowedTools"] + disallowedTools

        arguments += ["--add-dir", courseDir.path]
        if let deck = lecture.deckPath, !deck.isEmpty {
            arguments += ["--add-dir", (deck as NSString).deletingLastPathComponent]
        }

        var resultText = ""
        var failure: String?

        try await Shell.run(claude, arguments, cwd: courseDir, log: nil, onLine: { line in
            guard let event = StreamEvent(line: line) else { return }
            if let detail = event.progressDescription { onStage?(detail) }
            if let text = event.logText { onLog?(text) }
            if let result = event.finalResult { resultText = result }
            if let error = event.errorDetail { failure = error }
        })

        if let failure { throw RunFailed(detail: failure) }
        onLog?(resultText)

        return try locateNote(expected: noteURL, lecture: lecture, in: courseDir)
    }

    /// When the user leaves the topic blank, Claude names the file, so accept any
    /// note written for this lecture's date rather than one exact filename.
    private func locateNote(expected: URL, lecture: Lecture, in directory: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: expected.path) { return expected }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let candidates = contents.filter {
            $0.pathExtension == "md" && $0.lastPathComponent.hasPrefix(lecture.dateStamp)
        }
        guard let newest = candidates.max(by: { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return leftDate < rightDate
        }) else {
            throw RunFailed(detail: "no note file matching \(lecture.dateStamp)-*.md was written to \(directory.path)")
        }
        return newest
    }

    /// Writes an MCP config holding only what this destination needs, reusing the
    /// server definitions Claude Code already has authenticated.
    private func writeScopedMCPConfig(into directory: URL) throws -> URL {
        var servers: [String: Any] = [:]
        let existing = MCPRegistry.load()
        for name in settings.destination.requiredMCPServers {
            if let definition = existing[name] { servers[name] = definition }
        }
        let payload = ["mcpServers": servers]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        let url = directory.appendingPathComponent(".lecrec-mcp.json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Reads server definitions out of the user's Claude Code config so the app never
/// needs its own OAuth. Notion is project-scoped under the home directory, which
/// is why a plain inherited run from another cwd sees no Notion tools.
enum MCPRegistry {
    static func load() -> [String: Any] {
        let path = NSString(string: "~/.claude.json").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var merged: [String: Any] = [:]
        if let global = root["mcpServers"] as? [String: Any] {
            merged.merge(global) { current, _ in current }
        }
        if let projects = root["projects"] as? [String: Any] {
            for (_, value) in projects {
                guard let project = value as? [String: Any],
                      let servers = project["mcpServers"] as? [String: Any] else { continue }
                merged.merge(servers) { current, _ in current }
            }
        }
        return merged
    }

    static func isConfigured(_ name: String) -> Bool { load()[name] != nil }
}

private extension FileManager {
    func contents(atPath path: String) -> Data? { contents(atPath: path, options: []) }
    func contents(atPath path: String, options: Data.ReadingOptions) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path), options: options)
    }
}
