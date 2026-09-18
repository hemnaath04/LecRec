# Installing LecRec

## 1. Drag LecRec into Applications

## 2. Open it once

LecRec is signed ad hoc, not by a paid Apple developer account, so macOS blocks
the first launch. Since macOS 26 the old right-click-and-Open trick no longer
works. Do this instead:

1. Double-click LecRec. macOS says it cannot be opened.
2. Open **System Settings > Privacy and Security**, scroll down, and click
   **Open Anyway** next to LecRec.
3. Confirm. This is a one-time step.

Do it within about an hour of the warning, or macOS drops the entry and you have
to trigger the warning again.

## 3. Finish setup in the app

LecRec walks you through the rest and installs what it can for you:

| Needs | Why | Cost |
|---|---|---|
| Apple Silicon Mac | The transcription model is MLX-only | n/a |
| ffmpeg | Cleans the recording | free |
| parakeet-mlx | Transcribes on your Mac | free, about 2.3 GB on first run |
| Claude Code | Writes the note | **paid Claude plan, from 20 dollars a month** |
| Notion connected in Claude Code | Publishes the note | free |

LecRec then creates a **Course Notes** database in your own Notion workspace and
remembers its id. Nothing is shared with anyone else's workspace, and no audio or
note text ever leaves your machine except through your own Claude and Notion
accounts.

## Where things live

- Recordings, transcripts and notes: `~/Documents/course-notes/<COURSE>/`
- Settings: `~/Library/Application Support/LecRec/settings.json`
- Log: `~/Library/Logs/LecRec.log`

## Using it

Pick your course in the menu bar, optionally type the topic, press record. Stop
when class ends. LecRec cleans, transcribes, checks that the transcript covers the
whole recording, writes the note, and publishes it.

The audio file and the local Markdown are always written before anything is
published, so a failed publish never costs you the lecture.
