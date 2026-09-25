import Foundation

/// Appends to ~/Library/Logs/LecRec.log. A menu bar app has no console, so this
/// is the only way to see what happened during a lecture.
enum Diagnostics {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("LecRec.log")
    }()

    private static let queue = DispatchQueue(label: "tech.hemnaath.lecrec.log")

    /// Anyone watching the live monitor. The log is the only place the pipeline
    /// narrates itself, so the window subscribes here rather than tailing a file.
    private static var listeners: [String: (String) -> Void] = [:]
    private static let listenerLock = NSLock()
    /// Recent lines, so a window opened mid-run is not blank.
    private static var recent: [String] = []

    static func observe(_ key: String, _ handler: @escaping (String) -> Void) -> [String] {
        listenerLock.lock()
        listeners[key] = handler
        let backlog = recent
        listenerLock.unlock()
        return backlog
    }

    static func stopObserving(_ key: String) {
        listenerLock.lock()
        listeners.removeValue(forKey: key)
        listenerLock.unlock()
    }

    static func clearRecent() {
        listenerLock.lock()
        recent.removeAll()
        listenerLock.unlock()
    }

    static func log(_ message: String) {
        listenerLock.lock()
        recent.append(message)
        if recent.count > 400 { recent.removeFirst(recent.count - 400) }
        let handlers = Array(listeners.values)
        listenerLock.unlock()
        DispatchQueue.main.async { handlers.forEach { $0(message) } }

        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp)  \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
