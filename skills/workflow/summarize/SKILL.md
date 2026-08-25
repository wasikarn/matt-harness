---
name: summarize
description: "Compress a document, transcript, or pasted text into a BLUF-structured summary. Use when condensing long content for a reader. Delegates to the summarizer agent. Don't use for structured data extraction or code review."
model: inherit
effort: low
---

# Summarize

Compress arbitrary text — a report, transcript, article, spec, or thread — into the shortest form
that loses no fact the reader needs to act or decide. Delegates to the `summarizer` agent, which
owns the reader-identification → load-bearing-extraction → compression → fidelity-check procedure.

## Usage

Optionally name a local file path when invoking this skill — otherwise summarize the text
pasted alongside the invocation.

The agent only reads local files or text handed to it directly (no `Bash`, no fetch) — resolve a
URL or ticket key to its actual content before invoking this skill.

## Output Contract

The agent returns:

1. `tl;dr` — the single most important takeaway, one sentence (or one per throughline, if the
   source covers several unrelated topics).
2. `summary` — every fact, decision, and caveat the reader needs, structured to match the content
   (prose / bullets / table).
3. `detail` — only if the source has material worth drilling into beyond the summary.
4. `flagged_ambiguity` — only if the source itself was unclear or self-contradictory.
