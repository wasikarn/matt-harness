---
description: "Gate-report: ask/deny counts per gate from the gate-decisions journal, and mh skills unused in the last N sessions. Use for gate friction or stale skills."
name: gate-report
disable-model-invocation: true
model: inherit
effort: low
---

# Gate Report

Print an ask-count summary of `hooks/gates/_journal.py`'s own log,
`~/.local/share/kbg/metrics/gate-decisions.jsonl`. It covers every non-allow gate verdict
(ask/deny/`allow-suppressed`) across every session on this machine that ran with a gate wired to
`journal()`, broken down by gate id and by tool.

## Run

One Bash call. The script reads the log and prints the report; do not open the log yourself or
count rows by hand.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/gate-report.py"
```

`MH_GATE_JOURNAL_PATH=<path>` points the script at another log — the same env var
`hooks/gates/_journal.py` itself reads, so a test fixture or an alternate host's log works without
a second override name.

If the file is missing, the script prints `Gate journal not set up.` and exits 0. Relay that
line: the log fills only after a gate first asks or denies. Do not invent numbers.

## Skill usage

Which mh skills had no recorded use in the last N sessions (default 100; GH #474). Read-only and
machine-local: it reads `~/.local/share/kbg/metrics/skill-usage.jsonl`, never a gate and never
a `harness-audit` check, since the log differs per machine.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/skill-usage.py" [--sessions N]
```

It prints two lists with each skill's last-use date: model-invocable skills, then manual-only
ones (`disable-model-invocation: true`), because a manual-only skill is used only when typed and
rarely by nature. A missing log prints `Skill usage log not set up.`; relay that line.

- **Zero use is not broken.** A rare skill and a description that never matches look the same
  here. List the skills; a human decides keep, trim or fix the description.
- **N counts sessions that used an mh skill.** A session with no skill use leaves no row, so
  it is invisible; the header says `last X of Y sessions with an mh skill use`.
- **Typed uses are logged** (`source: typed`) next to model calls, so a manual-only skill's use
  does show up.

## Read back

Quote the script's counts as printed.

- **Ask-count only, never wait-time.** `_journal.py`'s row (`ts`, `id`, `tool_name`, `decision`,
  `session_id`) has no resolution timestamp, so this report cannot say how long a user took to
  answer a prompt.
- **`allow-suppressed` isn't a block.** `secret-scan.py` logs this decision when a same-line
  suppression marker (`gitleaks:allow` etc.) let a match through — it's informational, not a
  friction event, so don't fold it into an "interruptions" total without saying so. Since GH #378
  it writes one row per write with `count` (the matches suppressed in it); the script counts
  matches, so older one-row-per-match logs and newer ones add up the same way.
- **`would_deny`/`would_ask` rows are not blocks.** A rule listed in a gate's `SHADOW_RULES`
  (GH #337) only journals a match and allows the call. The "Shadow rules" section lists each
  such rule's count, session count and up to 3 sample commands. Read the samples: a rule is
  ready to enforce (delete its id from `SHADOW_RULES`) when its matches over several sessions
  are all real hits, with no false positive among them.
- **Session-less rows are left out.** A row with no `session_id` came from a test or a direct
  gate run, not a live hook call; the report skips it and prints `Ignored N session-less row(s)`.
  A large N means something is writing to the real journal without `MH_GATE_JOURNAL_PATH`
  (the real log once held 268,206 of them beside ~830 rows with an id); say so instead of
  folding them in.
- **A `session_id` is not proof of a live call.** Made-up ids (`test-session`, `s`, `t`) from
  older tests and from agents probing a gate by hand without `MH_GATE_JOURNAL_PATH` still count:
  178 of the real log's ~830 counted rows, 159 of its 161 `subagent-verdict-check` denies. Live ids
  are UUIDs, so the report prints a `Non-UUID session id(s)` line naming them. Quote it, and say
  a gate's count is mostly made-up ids when that line shows it. Another host's log may not use
  UUIDs, so they are named, not dropped.
- **A high count for one gate isn't automatically a problem.** It says a gate fired often, not
  that it was wrong to; compare against that gate's own false-positive history if one exists
  before recommending a change to it.
