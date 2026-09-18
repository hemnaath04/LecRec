import Foundation

/// An external tool LecRec needs, plus how to get it. Onboarding can run the
/// install itself, so a new user never has to translate an error into a command.
struct Dependency: Identifiable, Hashable {
    enum Kind: Hashable {
        case binary(String)          // must exist on PATH
        case mcpServer(String)       // must be configured in Claude Code
    }

    var id: String { title }
    var title: String
    var detail: String
    var kind: Kind
    /// Shell command that installs it, or nil when only the user can do it.
    var installCommand: String?
    /// Shown when there is no command we can safely run for them.
    var manualHint: String?
    var isRequired: Bool = true

    var isSatisfied: Bool {
        switch kind {
        case .binary(let name): return Shell.which(name) != nil
        case .mcpServer(let name): return MCPRegistry.isConfigured(name)
        }
    }

    static let homebrew = Dependency(
        title: "Homebrew",
        detail: "Package manager used to install ffmpeg.",
        kind: .binary("brew"),
        installCommand: nil,
        manualHint: "Install from https://brew.sh, then reopen LecRec.")

    static let ffmpeg = Dependency(
        title: "ffmpeg",
        detail: "Cleans the recording before transcription.",
        kind: .binary("ffmpeg"),
        installCommand: "brew install ffmpeg")

    static let uv = Dependency(
        title: "uv",
        detail: "Installs the on-device transcription model runner.",
        kind: .binary("uv"),
        installCommand: "curl -LsSf https://astral.sh/uv/install.sh | sh")

    static let parakeet = Dependency(
        title: "parakeet-mlx",
        detail: "Transcribes on this Mac. First run downloads about 2.3 GB.",
        kind: .binary("parakeet-mlx"),
        installCommand: "uv tool install parakeet-mlx -U")

    static let claude = Dependency(
        title: "Claude Code",
        detail: "Writes the note. Needs a paid Claude plan, from 20 dollars a month.",
        kind: .binary("claude"),
        installCommand: nil,
        manualHint: "Install from https://claude.com/claude-code, sign in, then reopen LecRec.")

    static func notion() -> Dependency {
        Dependency(
            title: "Notion connection",
            detail: "Publishes your notes. Connected through Claude Code, not through LecRec.",
            kind: .mcpServer("notion"),
            installCommand: "claude mcp add --transport http notion https://mcp.notion.com/mcp",
            manualHint: "After adding it, run `claude` once and approve the Notion sign in.")
    }

    static func all(for destination: Destination) -> [Dependency] {
        var list = [homebrew, ffmpeg, uv, parakeet, claude]
        if destination.requiredMCPServers.contains("notion") { list.append(notion()) }
        return list
    }
}

/// Runs install commands through a login shell so Homebrew and uv behave the way
/// they do in Terminal.
enum DependencyInstaller {
    static func install(_ dependency: Dependency,
                        log: @escaping (String) -> Void) async throws {
        guard let command = dependency.installCommand else {
            throw Shell.MissingTool(name: dependency.title,
                                    installHint: dependency.manualHint ?? "see the project README")
        }
        log("$ \(command)")
        try await Shell.run("/bin/zsh", ["-lc", command], log: log)
    }
}
