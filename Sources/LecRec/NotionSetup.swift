import Foundation

/// Creates the user's own Course Notes database during onboarding.
///
/// This is the change that made LecRec shareable at all. The earlier version
/// inherited one person's hardcoded Notion IDs, so anyone else who installed it
/// would have published into a workspace that was not theirs.
enum NotionSetup {
    struct Result: Decodable {
        var dataSourceId: String
        var pageUrl: String
        var parentPageId: String?
    }

    struct SetupFailed: LocalizedError {
        let detail: String
        var errorDescription: String? { "Could not set up your Notion database: \(detail)" }
    }

    /// Asks Claude Code, using the user's own Notion connection, to find or create
    /// the database and hand back its identifiers as structured output.
    /// `existing` is a database URL or id the user already has. When present we
    /// adopt it and only add missing Course options, rather than creating a
    /// second database alongside the one they already keep notes in.
    static func provision(courses: [Course],
                          existing: String? = nil,
                          log: @escaping (String) -> Void) async throws -> Result {
        let claude = try Shell.require("claude", hint: "install Claude Code")

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lecrec-setup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let mcpConfig = workDir.appendingPathComponent("mcp.json")
        let servers = MCPRegistry.load()
        guard let notion = servers["notion"] else {
            throw SetupFailed(detail: "the Notion server is not configured in Claude Code yet")
        }
        let payload = ["mcpServers": ["notion": notion]]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            .write(to: mcpConfig)

        let courseOptions = courses.map(\.notionCourse).joined(separator: ", ")
        let schema = """
        {"type":"object","properties":{\
        "dataSourceId":{"type":"string"},\
        "pageUrl":{"type":"string"},\
        "parentPageId":{"type":"string"}},\
        "required":["dataSourceId","pageUrl"]}
        """

        let trimmedExisting = existing?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt: String
        if let target = trimmedExisting, !target.isEmpty {
            prompt = """
            I already keep my lecture notes in a Notion database. Adopt it, do not \
            create a new one.

            The database is: \(target)

            1. Resolve it and confirm it is a database I can write to. If that \
            identifier does not resolve to a writable database, stop and say so.
            2. Report its properties. It should have a title property, a date property \
            and a select property for the course. If the select property is missing any \
            of these options, add the missing ones: \(courseOptions)
            3. Change nothing else. Do not rename it, do not delete properties, and do \
            not touch any existing rows.

            Return only the JSON object described by the schema: its data source id, its \
            page URL, and the id of the page it lives under if it has one.
            """
        } else {
            prompt = """
            Set up a lecture notes database in my Notion workspace, then report its \
            identifiers.

            1. Search my workspace for an existing database named "Course Notes". If one \
            already exists and has title, date and course properties, reuse it rather \
            than creating a duplicate.
            2. Otherwise create a new database named "Course Notes" at the top level of \
            my workspace, with these properties:
               - Title (title)
               - Date (date)
               - Course (select) with options: \(courseOptions)
            3. If it exists but is missing the Course options above, add the missing ones.

            Return only the JSON object described by the schema: the data source id of \
            that database, its page URL, and the id of the page it lives under if it has \
            one. Do not create any other page, and do not write any file.
            """
        }

        var output = ""
        try await Shell.run(claude, [
            "-p", prompt,
            "--permission-mode", "auto",
            "--model", "sonnet",
            "--output-format", "json",
            "--json-schema", schema,
            "--mcp-config", mcpConfig.path,
            "--allowedTools", "mcp__notion__*",
            "--disallowedTools", "WebFetch", "WebSearch", "Write", "Edit", "Bash", "Task",
            "--append-system-prompt",
            "You are running unattended during app setup. Never ask a question. "
                + "Touch nothing in the workspace beyond the Course Notes database.",
        ], cwd: workDir, log: { line in
            log(line.count > 200 ? String(line.prefix(200)) + "..." : line)
        }, onLine: { line in
            output += line + "\n"
        })

        return try parse(output)
    }

    private static func parse(_ output: String) throws -> Result {
        // The CLI prints one JSON envelope whose `result` holds the structured object.
        guard let data = output.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // Fall back to the last JSON-looking line, in case of extra output.
            guard let line = output.components(separatedBy: "\n")
                .last(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("{") }),
                  let lineData = line.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(Result.self, from: lineData)
            else { throw SetupFailed(detail: "could not read the setup response") }
            return decoded
        }

        if envelope["is_error"] as? Bool == true {
            throw SetupFailed(detail: envelope["result"] as? String ?? "unknown error")
        }

        if let structured = envelope["result"] {
            if let dictionary = structured as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: dictionary),
               let decoded = try? JSONDecoder().decode(Result.self, from: data) {
                return decoded
            }
            if let text = structured as? String,
               let data = text.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(Result.self, from: data) {
                return decoded
            }
        }
        throw SetupFailed(detail: "the setup response did not contain a database id")
    }
}
