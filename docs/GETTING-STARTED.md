# Getting started with LecRec

LecRec records a lecture and gives you back a structured, cross-checked note in
Notion. This page is everything you need, in order.

## Before you start

You need four things. LecRec installs the first two for you.

| | What | Cost |
|---|---|---|
| 1 | An Apple Silicon Mac (M1 or newer) | the transcription model is Apple Silicon only |
| 2 | ffmpeg and parakeet-mlx | free, installed for you, about 2.3 GB on first transcription |
| 3 | Claude Code, signed in | **a paid Claude plan, from 20 dollars a month** |
| 4 | Notion connected inside Claude Code | free |

Point 3 is not optional and LecRec cannot pay for it. Claude Code is what reads
the transcript and writes the note. There is no free Claude Code tier.

Nothing about your lecture leaves your Mac except through your own Claude and
Notion accounts. LecRec has no server and no account.

## 1. Install the app

Drag LecRec to Applications, then open it once.

macOS will refuse the first launch, because the app is not signed by a paid Apple
developer account. Since macOS 26 the old right-click-and-Open trick no longer
works. Do this instead:

1. Double-click LecRec. macOS says it cannot be opened. Dismiss that.
2. Open **System Settings > Privacy and Security**, scroll down, click
   **Open Anyway** next to LecRec, and confirm.

Do it within about an hour of the warning or the entry disappears and you have to
trigger it again. This is a one-time step.

## 2. Work through the four setup steps

Every step has a **?** button in the bottom left that explains that step. Use it.

**Step 2, requirements.** Anything marked missing has an **Install** button that
runs the command for you. Two exceptions you have to do yourself:

- **Claude Code**: get it from claude.com/claude-code, sign in, come back, press
  **Re-check**.
- **Notion connection**: press Install to add it, then run `claude` once in
  Terminal and approve the Notion sign in when it asks.

**Step 3, courses and destination.** Type your courses one per line, exactly how
you want them to read in Notion, for example `NLP CS 6120`.

Then pick where notes go:

- **Press "Find my databases"** and choose yours from the list. Easiest path.
- Or tick the box and paste the database link. Open the database in Notion as a
  full page, click **•••** at the top right, **Copy link**, and paste the whole
  URL. Do not try to trim it; the `?v=` part is a saved view and LecRec works out
  the rest.
- Or leave the box unticked and LecRec creates a **Course Notes** database for
  you, with Title, Date and Course properties already set up.

If you point LecRec at a database you already use, it will add any missing Course
options and change nothing else. It will not rename it, remove properties, or
touch existing rows.

## 3. Record a lecture

Click the waveform icon in your menu bar. Pick the course, optionally type the
topic, press **Start recording**. Press **Stop and process** when class ends.

Two things to watch while recording:

- **The level meter must move.** If it sits flat for 20 seconds LecRec warns you.
  A wrong input device is the one mistake you cannot fix after the fact.
- **You can close the window.** Recording continues, and so does processing.

Processing a 75 minute lecture takes a few minutes. The six steps show live, so
you can see what is happening and that earlier steps finished.

## What you get

```
~/Documents/course-notes/<COURSE>/
├── audio/        the original recording, and the cleaned copy
├── transcripts/  timestamped SRT
└── 2026-09-18-smoothing-and-perplexity.md
```

Plus a page in your Notion database with numbered sections, a Connections section
tying the lecture to earlier ones, open gaps as checkboxes, and self-test
questions.

The recording and the local Markdown are always written **before** anything is
published, so a failed publish never costs you the lecture.

## Honest limitations

- **Sitting far back hurts accuracy.** A laptop mic twelve rows from the lecturer
  is a hard constraint no model fixes. LecRec denoises and flags low coverage, but
  treat numbers, formulas and proper nouns in the transcript as unreliable. The
  note marks what it is unsure about instead of inventing an answer.
- **No slide deck attachment yet.** Until that lands, notes are built from the
  transcript alone, so every note opens a gap for the missing deck.
- **The transcript can be short.** If the recording started late, LecRec tells you
  the coverage percentage rather than quietly publishing a partial note.

## Where things live

- Notes and audio: `~/Documents/course-notes/`
- Settings: `~/Library/Application Support/LecRec/settings.json`
- Log, useful when something failed: `~/Library/Logs/LecRec.log`
