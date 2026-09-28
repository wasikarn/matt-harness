---
description: "Gate-report: ask/deny counts per gate from the gate-decisions journal. Use when checking how often gates interrupt writes. Not a wait-time/approval-latency metric (none logged)."
name: gate-report
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

## Read back

Quote the script's counts as printed.

- **Ask-count only, never wait-time.** `_journal.py`'s row (`ts`, `id`, `tool_name`, `decision`,
  `session_id`) has no resolution timestamp, so this report cannot say how long a user took to
  answer a prompt — an earlier draft of this gap (`docs/research/ai-native-sdlc-playbook-audit-2026-08-28.md`,
  Round 4) proposed an approval-wait-time metric and that was corrected before this was built.
- **`allow-suppressed` isn't a block.** `secret-scan.py` logs this decision when a same-line
  suppression marker (`gitleaks:allow` etc.) let a match through — it's informational, not a
  friction event, so don't fold it into an "interruptions" total without saying so.
- **A high count for one gate isn't automatically a problem.** It says a gate fired often, not
  that it was wrong to; compare against that gate's own false-positive history if one exists
  before recommending a change to it.
