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

        /// Notion hands back `collection://<uuid>` for a data source, but the
        /// create-pages tool wants the bare uuid.
        var normalizedDataSourceId: String {
            dataSourceId.replacingOccurrences(of: "collection://", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// One candidate database the user could publish into.
    struct Candidate: Decodable, Hashable {
        var title: String
        var dataSourceId: String
        var url: String?
    }

    private struct CandidateList: Decodable {
        var databases: [Candidate]
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

        // A pasted Notion link often arrives with a trailing newline, and a
        // double paste arrives as two lines. Take the first non-empty line only.
        let trimmedExisting = existing?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let prompt: String
        if let target = trimmedExisting, !target.isEmpty {
            prompt = """
            I already keep my lecture notes in Notion. Adopt what I point you at, do \
            not create a new database.

            What I gave you: \(target)

            1. Resolve it. It may be any of three things, and all three are normal \
            because a page link is what Notion's Copy link button produces:
               a. A data source, which is what you need. Use it.
               b. A database. Take its data source.
               c. A **page that contains a database**, inline or as a child. Look inside \
            it. If there is exactly one database, use that one. If there are several, \
            pick the one whose name or properties look like lecture or course notes, and \
            say in your reasoning which you picked and why.
            2. If none of those apply, or you cannot write to it, stop and say exactly \
            what you found instead.
            3. Check its properties: a title property, a date property, and a select \
            property for the course. If the select is missing any of these options, add \
            the missing ones: \(courseOptions)
            4. Change nothing else. Do not rename it, do not remove properties, do not \
            reorder them, and do not touch any existing rows.

            Return only the JSON object described by the schema: the data source id, its \
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

    /// Lists the databases in the user's workspace that look like notes databases,
    /// so nobody has to go hunting for an id in a URL.
    static func findDatabases(log: @escaping (String) -> Void) async throws -> [Candidate] {
        let claude = try Shell.require("claude", hint: "install Claude Code")
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lecrec-find-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let mcpConfig = workDir.appendingPathComponent("mcp.json")
        guard let notion = MCPRegistry.load()["notion"] else {
            throw SetupFailed(detail: "the Notion server is not configured in Claude Code yet")
        }
        try JSONSerialization.data(withJSONObject: ["mcpServers": ["notion": notion]],
                                   options: [.prettyPrinted]).write(to: mcpConfig)

        let schema = """
        {"type":"object","properties":{"databases":{"type":"array","items":{\
        "type":"object","properties":{"title":{"type":"string"},\
        "dataSourceId":{"type":"string"},"url":{"type":"string"}},\
        "required":["title","dataSourceId"]}}},"required":["databases"]}
        """

        var output = ""
        try await Shell.run(claude, [
            "-p", """
            List the databases in my Notion workspace that could hold lecture or course \
            notes. Prefer ones whose name mentions notes, lectures, courses or classes, \
            but include any database with a title property and a date property. Return at \
            most 12, most recently edited first. Return only the JSON described by the \
            schema. Do not create, rename or modify anything.
            """,
            "--permission-mode", "auto",
            "--model", "sonnet",
            "--output-format", "json",
            "--json-schema", schema,
            "--mcp-config", mcpConfig.path,
            "--allowedTools", "mcp__notion__notion-search", "mcp__notion__notion-fetch",
            "--disallowedTools", "WebFetch", "WebSearch", "Write", "Edit", "Bash", "Task",
            "--append-system-prompt",
            "You are running unattended during app setup. Never ask a question. Read only.",
        ], cwd: workDir, log: { line in
            log(line.count > 160 ? String(line.prefix(160)) + "..." : line)
        }, onLine: { line in output += line + "\n" })

        guard let data = output.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SetupFailed(detail: "could not read the database list") }
        if envelope["is_error"] as? Bool == true {
            throw SetupFailed(detail: envelope["result"] as? String ?? "unknown error")
        }
        guard let structured = envelope["result"] else {
            throw SetupFailed(detail: "no databases came back")
        }
        let payload: Data?
        if let dictionary = structured as? [String: Any] {
            payload = try? JSONSerialization.data(withJSONObject: dictionary)
        } else if let text = structured as? String {
            payload = text.data(using: .utf8)
        } else {
            payload = nil
        }
        guard let payload, let list = try? JSONDecoder().decode(CandidateList.self, from: payload)
        else { throw SetupFailed(detail: "the database list could not be read") }
        return list.databases
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
