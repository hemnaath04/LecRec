import Foundation

enum Prompt {
    /// Appended to the default system prompt. States the boundaries in words, as
    /// the last of the four containment layers rather than the only one.
    static func systemConstraints(settings: Settings) -> String {
        let root = settings.notesRoot
        let editRule = settings.closeResolvedGaps
            ? """
              You may edit an earlier lecture's note in exactly one way: ticking a gap \
              it had left open, with the answer and where the answer came from. Never \
              rewrite its prose, never change its conclusions, and never touch a note \
              for a course other than the one named in the prompt.
              """
            : """
              Never modify or delete a note for a different date. Earlier notes are \
              read-only context.
              """

        return """
        You are running unattended inside LecRec, a lecture-notes app. There is no \
        human watching this session, so never ask a question, never offer options, and \
        never wait for confirmation. Decide and act.

        Boundaries, which are absolute:
        - Only read and write inside \(root) and any directory explicitly added to this \
        session. Never read the user's other projects, mail, code, credentials, or shell \
        history, and never open a file merely because it looked interesting.
        - \(editRule)
        - Never run a command that installs, uninstalls, upgrades, commits, pushes, or \
        deletes anything. No git, no package managers, no rm.
        - Never write to any destination other than the one named in the prompt.
        - Never emit an em dash in the note, in a commit, or in any Notion block. Use \
        commas, colons and periods.

        If a source is missing or a step is impossible, finish everything else, write the \
        note anyway, and record the gap in the note's Gaps section. A partial note on disk \
        is always better than no note.
        """
    }

    static func buildNote(lecture: Lecture,
                          transcript: URL,
                          coverage: CoverageReport,
                          noteURL: URL,
                          settings: Settings) -> String {
        let deckLine = lecture.deckPath.flatMap { $0.isEmpty ? nil : $0 }
            .map { "- Slide deck: \($0)" }
            ?? "- Slide deck: none provided for this lecture. Say so in the note and open a gap for it."

        let naming = lecture.needsGeneratedSlug
            ? """
              - Write the local Markdown to \(noteURL.deletingLastPathComponent().path)/\
              \(lecture.dateStamp)-<slug>.md, choosing a short kebab-case slug from the \
              lecture's actual topic, for example \(lecture.dateStamp)-smoothing-and-perplexity.md
              """
            : "- Write the local Markdown to: \(noteURL.path)"

        return """
        Process one lecture into a finished note. Use the \(SkillInstaller.skillName) \
        skill; it owns the note structure and the source precedence. Do not re-derive \
        any of that.

        Lecture:
        - Course: \(lecture.course.name), Notion Course property value "\(lecture.course.notionCourse)"
        \(destinationIdentifiers(settings: settings))
        - Date: \(lecture.dateStamp)
        - Timestamped transcript (SRT, from parakeet-mlx on device): \(transcript.path)
        \(deckLine)
        \(naming)

        Recording quality context, which matters for how much you trust the transcript:
        - \(coverage.summary)
        - The audio was captured on a MacBook Air built-in microphone from a back row of \
        the lecture hall, then denoised. Treat proper nouns, numbers and formulas in the \
        transcript as unreliable. Correct only what is unambiguous and list the rest \
        verbatim in the Gaps section rather than guessing.

        Steps, in order:
        \(continuityStep(settings: settings, lecture: lecture))
        \(writeStep(settings: settings))
        \(publishStep(settings: settings))
        \(reportStep(settings: settings))
        """
    }

    /// The skill deliberately holds no workspace IDs, so the app supplies them.
    private static func destinationIdentifiers(settings: Settings) -> String {
        guard settings.destination == .notion else { return "" }
        guard !settings.notionDataSourceID.isEmpty else {
            return "- Notion data source: NOT CONFIGURED. Write the local Markdown and "
                + "record this as a gap; do not attempt to publish."
        }
        return "- Notion data source id to publish into: \(settings.notionDataSourceID)"
    }

    // MARK: - Steps

    private static func continuityStep(settings: Settings, lecture: Lecture) -> String {
        guard settings.linkPreviousLectures else {
            return "1. Skip straight to writing the note; do not look up earlier lectures."
        }
        return """
        1. First, build the course context. Find the \(settings.continuityLookback) most \
        recent existing notes for \(lecture.course.name) before \(lecture.dateStamp): search \
        Notion's Course Notes database filtered to Course = "\(lecture.course.notionCourse)", \
        and also glob \(settings.notesRoot)/\(lecture.course.slug)/*.md. Read them and pull out:
           a. Terms already defined, so you reuse the course's established wording instead \
        of redefining a term the professor introduced two weeks ago.
           b. Open gaps and unanswered questions from those notes.
           c. The running threads: what problem the course has been building toward, and \
        where this lecture sits in that arc.
        """
    }

    private static func writeStep(settings: Settings) -> String {
        var step = """
        2. Write the local Markdown note. Do this before any publish call; that file is \
        the artifact that must survive even if publishing fails.
        """
        guard settings.linkPreviousLectures else { return step }
        step += """
        \n   Beyond the standard sections, this note must earn its place in the course:
           - A "Connections" section naming which earlier lectures this builds on, what \
        specifically carried over, and a one-line reminder of that earlier idea so the note \
        is readable without opening the other one.
           - Where today's material answers a question an earlier note left open, say so \
        explicitly: "this closes the gap from <date> about X, the answer is Y".
           - Where today's material contradicts or refines something an earlier note \
        claimed, flag it plainly rather than leaving two notes disagreeing.
           - Where a concept is a special case, generalisation or counterpart of an earlier \
        one, say which, since that relationship is the thing worth remembering at exam time.
           - Self-test questions that span lectures, not only today's slides.
        """
        if settings.closeResolvedGaps {
            step += """
            \n   Then tick off the gaps this lecture resolved on the earlier notes \
            themselves, both the local Markdown and the Notion page, changing "- [ ]" to \
            "- [x]" and appending the answer with today's date. Change nothing else on \
            those notes.
            """
        }
        return step
    }

    private static func publishStep(settings: Settings) -> String {
        switch settings.destination {
        case .markdown:
            return "3. Publishing is disabled; the local Markdown file is the final output. Do not call any MCP tool."
        case .notion:
            return """
            3. Publish to Notion with the notion MCP tools, into the data source id \
            given above, following the skill's publish steps exactly, including re-inserting the stripped H1 and \
            appending the body in chunks. If a page already exists for this course and \
            date, revise that page in place rather than creating a second one.
            """
        case .appleNotes:
            return """
            3. Publish into Apple Notes with osascript, in the folder \
            "\(settings.appleNotesFolder)". Apple Notes cannot render tables or equation \
            blocks, so flatten those to indented plain text and keep the section numbering.
            """
        case .obsidian:
            return """
            3. Publish by writing the note into the Obsidian vault at \
            \(settings.obsidianVaultPath), keeping the same filename, and turning \
            references to earlier lectures into wikilinks where a matching note exists.
            """
        }
    }

    private static func reportStep(settings: Settings) -> String {
        let extras = settings.linkPreviousLectures
            ? ", the number of earlier lectures you linked to, and the number of earlier gaps this lecture closed"
            : ""
        return """
        4. Finish by printing one line: the destination URL or path, the local file path, \
        the coverage percentage, the number of open gaps\(extras).
        """
    }
}
