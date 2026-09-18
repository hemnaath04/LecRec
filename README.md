# Lectern

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
re-run. Lectern always writes an audio file and always writes local Markdown
before touching the network.

## Build

No Xcode required, Command Line Tools is enough.

```bash
./scripts/preflight.sh      # names any missing dependency and how to install it
./scripts/build.sh release  # produces build/Lectern.app
open build/Lectern.app
```

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

## Logs

`~/Library/Logs/Lectern.log`. A menu bar app has no console, and this is the only
record of what happened during a lecture.
