import Foundation

/// One line of `--output-format stream-json`, reduced to what the UI needs.
struct StreamEvent {
    private let json: [String: Any]

    init?(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        json = object
    }

    var type: String { json["type"] as? String ?? "" }

    /// A short, human phrase for the menu bar popover while the run proceeds.
    var progressDescription: String? {
        guard type == "assistant",
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else { return nil }

        for block in content {
            guard block["type"] as? String == "tool_use",
                  let name = block["name"] as? String else { continue }
            let input = block["input"] as? [String: Any] ?? [:]
            return Self.phrase(forTool: name, input: input)
        }
        return nil
    }

    /// Assistant prose, useful in the log pane but too long for the popover.
    var logText: String? {
        guard type == "assistant",
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else { return nil }
        let texts = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    var finalResult: String? {
        guard type == "result", json["is_error"] as? Bool != true else { return nil }
        return json["result"] as? String
    }

    var errorDetail: String? {
        guard type == "result" else { return nil }
        if json["is_error"] as? Bool == true {
            return json["result"] as? String ?? json["subtype"] as? String ?? "unknown error"
        }
        if let status = json["api_error_status"] as? String { return "API error \(status)" }
        return nil
    }

    private static func phrase(forTool name: String, input: [String: Any]) -> String {
        let file = (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }

        switch name {
        case "Read":
            return file.map { "Reading \($0)" } ?? "Reading a source"
        case "Write":
            return file.map { "Writing \($0)" } ?? "Writing the note"
        case "Edit":
            return file.map { "Revising \($0)" } ?? "Revising the note"
        case "Glob", "Grep":
            return "Looking for the slide deck"
        case "Skill":
            return "Loading the course-notes skill"
        case "Bash":
            let command = input["command"] as? String ?? ""
            if command.contains("pdftoppm") { return "Rendering handwritten pages" }
            if command.contains("pdftotext") { return "Extracting the deck text" }
            if command.contains("python3") { return "Extracting the deck" }
            return "Running a local command"
        case let mcp where mcp.hasPrefix("mcp__notion__"):
            let action = mcp.replacingOccurrences(of: "mcp__notion__notion-", with: "")
            switch action {
            case "create-pages": return "Creating the Notion page"
            case "search", "fetch": return "Checking Notion for an existing note"
            case "create-file-upload": return "Uploading handwriting images"
            default: return "Notion: \(action.replacingOccurrences(of: "-", with: " "))"
            }
        default:
            return "Working: \(name)"
        }
    }
}
