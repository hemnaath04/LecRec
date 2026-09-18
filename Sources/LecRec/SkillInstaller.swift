import Foundation

/// Copies the bundled skill into the user's Claude Code skills directory.
///
/// The skill ships inside the app so a new user installs nothing by hand, and it
/// is named `lecrec-course-notes` so it can never collide with a skill the user
/// already wrote themselves.
enum SkillInstaller {
    static let skillName = "lecrec-course-notes"

    static var destination: URL {
        URL(fileURLWithPath: NSString(string: "~/.claude/skills").expandingTildeInPath)
            .appendingPathComponent(skillName, isDirectory: true)
    }

    static var bundledSource: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("skills/\(skillName)", isDirectory: true)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("SKILL.md").path)
    }

    /// Always overwrites, so shipping a fixed skill in a new build actually lands.
    static func install() throws {
        guard let source = bundledSource,
              FileManager.default.fileExists(atPath: source.path) else {
            throw Shell.MissingTool(
                name: "bundled skill",
                installHint: "rebuild LecRec with ./scripts/build.sh so Resources/skills is copied in")
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
