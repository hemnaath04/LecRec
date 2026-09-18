---
name: lecrec-course-notes
description: |
  Turn one university lecture into an exam-ready Notion note. Merges the
  timestamped transcript LecRec produced, the instructor's slide deck if one was
  provided, and any handwritten annotations, cross-checks them against each other,
  and publishes into the user's own Course Notes database. Invoked by the LecRec
  app; the app supplies every identifier in the prompt.
license: MIT
compatibility: claude-code
---

# Course notes: lecture into a published note

Three sources in, one page out:

```
LecRec transcript (SRT, timestamped) ─┐
Slide deck (.pptx / .pdf)             ├─→ cross-check ─→ local .md ─→ published page
Handwritten annotations ──────────────┘
```

Never publish from one source alone. The cross-check is the whole value.

## Identifiers come from the prompt, never from this file

The calling app passes the Notion data source ID, the course name and the output
path on every run. This skill is installed per user, so it must not contain
anyone's workspace IDs. If an identifier you need is missing from the prompt,
write the local Markdown anyway and record the missing identifier as a gap.

## Precedence when sources disagree

**handwriting > printed slide > transcript**

The transcript is raw ASR. It garbles proper nouns, numbers and formulas,
especially when the microphone was far from the speaker. The printed slide is
authoritative for wording but silent on anything said aloud only. The handwriting
is where the actual teaching happens.

## Check every time

- **Does the transcript cover the whole lecture?** The app reports coverage in the
  prompt. Below 95 percent, say so in the note and name what is missing.
- **Every number.** Transcripts mangle figures; slides and handwriting have them right.
- **Worked examples.** Transcripts drop arithmetic; the board has it.
- **Image-only slides.** They carry no extractable text. Note which slide numbers
  they are, and never present a reconstructed diagram as if traced from the original.
- **Garbles.** Correct only what is unambiguous. List the rest verbatim in Gaps
  rather than guessing.

## Note shape

H1 → metadata table → numbered sections `§1..§N` → Connections to earlier
lectures → Gaps as unchecked to-dos → Self-test questions → Next steps.

- Number sections and cross-reference them. Verify every `§n` target exists.
- No em dashes. Use commas, colons and periods.
- Keep lecture-only material: anecdotes, student questions, asides. That is what
  the slides do not have.
- Exam-facing content goes in tables and callouts, not prose paragraphs.

## Publishing to Notion

1. `notion-create-pages` with `parent: {type: data_source_id, data_source_id: <from the prompt>}`.
   **It strips a leading H1**, so re-insert it with `insert_content` at `position: start`.
2. Append the body in chunks with `insert_content` at `position: end`. Do not trim to fit.
3. Upload images, then splice them in with `update_content` anchored on the
   sentence each image belongs to. Put each image where it teaches, never in a
   dump at the end.
4. Fetch the page once at the end and verify.

## Revisiting a note later

When a deck arrives after the note is published, do not rewrite the page. Splice
with `update_content`: fix wrong claims in place, flip resolved gaps to `- [x]`
with the answer and its slide number, and add the images. Keep the local `.md` in
sync so the two never diverge.
