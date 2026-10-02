import Foundation

/// Class code, usually the Jupyter notebook worked through during the lecture.
///
/// A raw .ipynb is JSON carrying base64 images, execution counts and stream
/// output, which is both unreadable and expensive to hand to a model. So a
/// notebook is flattened to Markdown first: markdown cells as prose, code cells
/// as fenced blocks, and output kept only when it is text and short enough to
/// mean something. Plain source files are passed through untouched.
enum CodeNotes {
    /// Output longer than this says nothing a note needs, so it is cut.
    private static let maxOutputLines = 12
    private static let maxOutputChars = 1200

    static func isNotebook(_ path: String) -> Bool {
        (path as NSString).pathExtension.lowercased() == "ipynb"
    }

    /// Returns the path the prompt should point at: a flattened sibling for a
    /// notebook, or the original path for anything else.
    static func prepare(_ path: String, in courseDir: URL, log: ((String) -> Void)? = nil) -> String? {
        guard FileManager.default.fileExists(atPath: path) else {
            log?("code note is missing: \(path)")
            return nil
        }
        guard isNotebook(path) else { return path }

        guard let flattened = flatten(path) else {
            log?("could not read the notebook, passing the raw file instead: \(path)")
            return path
        }
        let dir = courseDir.appendingPathComponent("code", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".ipynb", with: "", options: .caseInsensitive)
        let out = dir.appendingPathComponent("\(base).md")
        do {
            try flattened.write(to: out, atomically: true, encoding: .utf8)
            log?("flattened \(base).ipynb to \(out.lastPathComponent)")
            return out.path
        } catch {
            log?("could not write the flattened notebook: \(error.localizedDescription)")
            return path
        }
    }

    static func flatten(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cells = root["cells"] as? [[String: Any]]
        else { return nil }

        let language = ((root["metadata"] as? [String: Any])?["language_info"]
            as? [String: Any])?["name"] as? String ?? "python"

        var out = ["# \((path as NSString).lastPathComponent)", ""]
        for (index, cell) in cells.enumerated() {
            let source = text(cell["source"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }
            switch cell["cell_type"] as? String {
            case "markdown":
                out.append(source)
            case "code":
                out.append("```\(language)")
                out.append(source)
                out.append("```")
                if let rendered = outputs(cell["outputs"]) {
                    out.append("Output:")
                    out.append("```")
                    out.append(rendered)
                    out.append("```")
                }
            default:
                out.append("```")
                out.append(source)
                out.append("```")
            }
            out.append("")
            _ = index
        }
        return out.joined(separator: "\n")
    }

    /// A notebook stores text as either a string or an array of lines.
    private static func text(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let lines = value as? [String] { return lines.joined() }
        return ""
    }

    private static func outputs(_ value: Any?) -> String? {
        guard let list = value as? [[String: Any]] else { return nil }
        var pieces: [String] = []
        for output in list {
            switch output["output_type"] as? String {
            case "stream":
                pieces.append(text(output["text"]))
            case "execute_result", "display_data":
                // Images and HTML are skipped: a note cannot use a base64 PNG,
                // and one plot can be larger than the whole rest of the file.
                if let plain = (output["data"] as? [String: Any])?["text/plain"] {
                    pieces.append(text(plain))
                }
            case "error":
                let name = output["ename"] as? String ?? "Error"
                let value = output["evalue"] as? String ?? ""
                pieces.append("\(name): \(value)")
            default:
                break
            }
        }
        var joined = pieces.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }

        var lines = joined.components(separatedBy: .newlines)
        if lines.count > maxOutputLines {
            lines = Array(lines.prefix(maxOutputLines)) + ["... output truncated"]
            joined = lines.joined(separator: "\n")
        }
        if joined.count > maxOutputChars {
            joined = String(joined.prefix(maxOutputChars)) + "\n... output truncated"
        }
        return joined
    }
}
