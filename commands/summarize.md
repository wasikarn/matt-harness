---
description: Compress a document, transcript, or pasted text into a BLUF-structured summary. Delegates to the summarizer agent.
name: summarize
model: inherit
effort: low
---

# Summarize

Compress arbitrary text — a report, transcript, article, spec, or thread — into the shortest form
that loses no fact the reader needs to act or decide. Delegates to the `summarizer` agent, which
owns the reader-identification → load-bearing-extraction → compression → fidelity-check procedure.

## Usage

`/summarize [path]` — summarize a local file.
`/summarize` with pasted text in the same message — summarize that text directly.

The agent only reads local files or text handed to it directly (no `Bash`, no fetch) — resolve a
URL or ticket key to its actual content before invoking this command.

## Output Contract

The agent returns:

1. `tl;dr` — the single most important takeaway, one sentence (or one per throughline, if the
   source covers several unrelated topics).
2. `summary` — every fact, decision, and caveat the reader needs, structured to match the content
   (prose / bullets / table).
3. `detail` — only if the source has material worth drilling into beyond the summary.
4. `flagged_ambiguity` — only if the source itself was unclear or self-contradictory.

## Arguments

$ARGUMENTS:
- optional target file path; if omitted, summarize the text pasted alongside the command
