import Foundation

/// Runs external binaries with a resolved absolute path. GUI apps inherit a
/// minimal PATH, so tools installed by Homebrew or uv are invisible unless
/// looked up explicitly.
enum Shell {
    static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        NSString(string: "~/.local/bin").expandingTildeInPath,
        "/usr/bin",
        "/bin",
    ]

    struct MissingTool: LocalizedError {
        let name: String
        let installHint: String
        var errorDescription: String? {
            "\(name) was not found. Install it with: \(installHint)"
        }
    }

    struct Failed: LocalizedError {
        let tool: String
        let code: Int32
        let output: String
        var errorDescription: String? {
            "\(tool) exited with code \(code).\n\(output.suffix(2000))"
        }
    }

    static func which(_ name: String) -> String? {
        for base in searchPaths {
            let candidate = base + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static func require(_ name: String, hint: String) throws -> String {
        guard let path = which(name) else { throw MissingTool(name: name, installHint: hint) }
        return path
    }

    /// Runs to completion, streaming stdout and stderr lines to `log`.
    @discardableResult
    static func run(_ executable: String,
                    _ arguments: [String],
                    cwd: URL? = nil,
                    environment: [String: String]? = nil,
                    log: ((String) -> Void)? = nil,
                    onLine: ((String) -> Void)? = nil) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        environment?.forEach { env[$0.key] = $0.value }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var collected = ""
        let lock = NSLock()
        var pending = ""

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            lock.lock()
            collected += text
            pending += text
            var lines = pending.components(separatedBy: "\n")
            pending = lines.removeLast()
            lock.unlock()
            for line in lines where !line.isEmpty {
                log?(line)
                onLine?(line)
            }
        }

        try process.run()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        pipe.fileHandleForReading.readabilityHandler = nil

        // Drain whatever landed between the last read and termination.
        if let rest = try? pipe.fileHandleForReading.readToEnd(),
           let text = String(data: rest, encoding: .utf8), !text.isEmpty {
            lock.lock(); collected += text; lock.unlock()
            text.components(separatedBy: "\n").filter { !$0.isEmpty }.forEach {
                log?($0); onLine?($0)
            }
        }

        guard process.terminationStatus == 0 else {
            throw Failed(tool: (executable as NSString).lastPathComponent,
                         code: process.terminationStatus, output: collected)
        }
        return collected
    }
}
