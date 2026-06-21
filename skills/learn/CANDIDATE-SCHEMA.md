# learn-capture candidate schema

The single contract that `hooks/session/learn-capture.sh` (writer),
`scripts/read-candidates.sh` (reader), and `kbg:learn` Step 0 (consumer) all cite.
Passive capture is **default-ON** (opt out with `KBG_LEARN_CAPTURE=0`) and **advisory-only**
— it journals + queues, never mutates the repo, never gates. See
[`docs/adr/0002-addendum-passive-capture.md`](../../docs/adr/0002-addendum-passive-capture.md).

## Queue location (source of record — both consumers compute it identically)

```
<project-mem-dir>/_candidates/queue.jsonl
```

where `<project-mem-dir>` is derived **from the transcript's own parent dir** (the slug
Claude Code itself chose), NOT a recomputed CWD/git slug:

- **writer + reader with a transcript in hand:** `<project-mem-dir> = dirname(<transcript_path>)/memory`
- **fallback only (no transcript):** `~/.claude/projects/<slug>/memory` where
  `slug = ${CLAUDE_PROJECT_DIR:-$PWD}` with every `/` → `-`.

Both paths land in the **same** out-of-repo memory store (`~/.claude/projects/<slug>/memory/`),
so the queue is never in `git status` and never in the L3 cage's reach. Deriving from the
transcript parent is load-bearing: a recomputed CWD-slug and a git-toplevel-slug **diverge**
on a subdir/monorepo launch → writer and reader pick different dirs → silent zero candidates.

## Row shape (JSONL, append-only)

One JSON object per line. No `confidence` field at capture — confidence is computed at review.

| field | type | meaning |
|---|---|---|
| `ts` | string | ISO-8601 UTC capture time |
| `session_id` | string | source session (`no-sid` if absent) |
| `project_slug` | string | the transcript-parent dir basename (provenance) |
| `kind` | string | `correction` \| `preference` \| `workflow` |
| `trigger` | string | the matched signal phrase (scrubbed) |
| `evidence` | string | the surrounding user-turn snippet (scrubbed, ≤280 chars) |
| `seen_count` | int | times this trigger/evidence pair was seen (writer sets 1; review merges) |
| `first_seen` | string | ISO date first captured |
| `last_seen` | string | ISO date most recently captured |
| `scope` | string | `repo` (default — captured under a project dir) |
| `source` | string | `learn-capture` (provenance; never a secret-named field) |
| `status` | string | `open` (default) \| `rejected` \| `promoted` (set by the gated flow) |

## Confidence — ORDERING signal ONLY (NON-NEGOTIABLE)

Computed at review time (reader + `kbg:learn` Step 0), never written by the hook, never compared
against a threshold to trigger any action. It only sorts the review list shown at the
`AskUserQuestion` gate.

```python
def clamp(lo, hi, x):
    return max(lo, min(hi, x))

# weeks_since(last_seen): floor of (today - last_seen) in days / 7
confidence = clamp(0.0, 1.0,
                   0.30
                   + min(0.05 * (seen_count - 1), 0.50)
                   - 0.02 * weeks_since(last_seen))
```

**The line that keeps this out of L4:** no value of `confidence` ever fires an action. If you
ever find a `confidence >= …` comparison that gates a write/apply, that is a bug — audit **#47**
CRIT-flags it.

## Secret-scrub (writer, before any append) — redact-whole-row fail-safe

The `_lib.sh` redactor only runs inside `journal_append`; direct queue writes bypass it, so the
writer scrubs **before** writing. Mirror the `_lib.sh` deny-list:

- **key/value names:** `password|api_key|secret|token|credential`
- **value shapes:** `AKIA[0-9A-Z]{16}` · `gh[pousr]_[A-Za-z0-9]{20,}` · `sk-[A-Za-z0-9]{20,}` ·
  `xox[baprs]-[A-Za-z0-9-]{10,}` · `-----BEGIN[A-Z ]*PRIVATE KEY` · `user:pass@` URLs

**Fail-safe:** on ANY match in `trigger` or `evidence`, drop the **whole row** (never write a
partially-redacted snippet). Over-dropping is acceptable; a leaked secret is not.

## Promotion

`kbg:learn` strips the staging fields (`seen_count`/`first_seen`/`last_seen`/`scope`/`source`/
`status`) and writes a real `memory/<slug>.md` via its existing Step-5 writer, then `--archive`s
the queue row. The queue is staging; the memory file is the durable artifact.
