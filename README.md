# LecRec

A macOS menu bar app that turns one button press into a finished lecture note.

```
Start  →  records to disk incrementally, live level meter, elapsed clock
Stop   →  ffmpeg denoise  →  parakeet-mlx (on device)  →  coverage check
       →  claude -p, scoped to this lecture, using the course-notes skill
       →  local Markdown first, then Notion
```

## Why it is shaped this way

The pipeline it replaces lost a third of a lecture: a live dictation transcript
was the only artifact, so when the capture started late there was nothing to
re-run. LecRec always writes an audio file and always writes local Markdown
before touching the network.

## Install

Grab the DMG from Releases and follow [docs/INSTALL.md](docs/INSTALL.md). First
launch walks you through the rest and installs what it safely can.

Needs an Apple Silicon Mac, and a paid Claude plan for the note writing. Recording
and transcription are free and run entirely on your machine.

## Build from source

No Xcode required, Command Line Tools is enough.

```bash
./scripts/preflight.sh       # names any missing dependency and how to install it
./scripts/build.sh release   # produces build/LecRec.app
./scripts/package.sh         # produces build/LecRec-<version>.dmg
open build/LecRec.app
```

Set `DEVELOPER_ID` (and optionally `NOTARY_PROFILE`) before `package.sh` to sign
and notarize instead of shipping an ad-hoc signature.

## Containment

The spawned Claude Code run is boxed in by four independent layers, strongest first:

1. `--mcp-config` declares only the servers the chosen destination needs, so the
   other configured servers are never loaded.
2. `--disallowedTools` hard-denies WebFetch, WebSearch, Task, and every mutating
   shell command.
3. cwd plus `--add-dir` bound file access to the lecture's own folders.
4. `--append-system-prompt` states the remaining rules in words.

Verified in a live run: `WebSearch: no`, `Notion: yes`, zero permission denials.

Notion auth is inherited from Claude Code's existing OAuth. The app implements no
credentials of its own, and any MCP-based destination added to Claude Code later
becomes available here without code changes.

Every install gets its own Notion database, created or adopted during onboarding.
Nothing about the notes destination is hardcoded to one workspace.

## Logs

`~/Library/Logs/LecRec.log`. A menu bar app has no console, and this is the only
record of what happened during a lecture.
