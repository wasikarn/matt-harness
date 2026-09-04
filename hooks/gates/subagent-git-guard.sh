#!/usr/bin/env bash
# Gate: a subagent may not run a repo-wide-mutating git subcommand via Bash
# -- only the main session may, and only because nothing else is writing in
# the shared tree. Reads the PreToolUse JSON payload from stdin; exits 2 to
# block.
#
# Why: issue #135 (2026-09-04) recorded two real incidents in one session on
# a shared working tree -- a dispatched builder swept a peer session's
# CLAUDE.md into commit 6603c384, and a separate dispatched subagent ran
# `git stash` / `git stash pop` over a peer's mid-edit files. Both are
# exactly the "No repo-wide git in a concurrent wave" rule
# skills/workflow/orchestrate/f9-template.md already states in prose (its
# Constraints (always) section: "no stash, checkout, reset, clean, restore.
# Scope every command to FILES YOU OWN... plain git stash/stash pop are not
# [denied], and are exactly the pair that raced in the incident this rule
# comes from") -- until this gate, nothing enforced it computationally, the
# same gap agent-recursion-guard.sh and task-complete-separation.sh closed
# for their own dispatch-only-from-main rules.
#
# Scope, checked against the LIVE content of hooks/gates/irrecoverable.sh
# (read fresh 2026-09-04, mid-widen by a concurrent session -- re-read that
# file directly rather than trusting exact conditions here if this drifts):
# irrecoverable.sh ALREADY denies, unconditionally, for every session
# (main included, not just subagents): `git reset --hard`; `git clean -f`
# and bundled short-flag -f forms (-xf etc); `git checkout --` / `git
# checkout .` / `git checkout -f` / `git checkout <tree-ish> <path>` (2+
# non-flag args); and `git restore <pathspec>` whenever it targets the
# worktree (default mode, or --worktree -- the destructive case; --staged
# alone is deliberately allowed there as recoverable). This gate does NOT
# re-implement any of those checks -- duplicating an existing unconditional
# deny gains nothing and only adds a second place to keep in sync. What
# irrecoverable.sh does NOT cover, for ANY session, is a bare/non-force
# `git stash`, `git reset`, or `git clean` -- exactly the shapes that raced
# in the issue #135 incident. Those three verbs are this gate's entire
# scope, and only for subagents.
#
# Discriminant: `agent_id` present in the PreToolUse payload == an actual
# subagent call (code.claude.com/docs/en/hooks, confirmed 2026-08-31 by the
# two sibling gates below); keyed the same way, for the same reason --
# agent_type is ALSO set for a top-level `claude --agent <name>` MAIN
# session, which legitimately needs every git subcommand this gate denies
# (that over-block was a real bug caught in agent-recursion-guard.sh and
# task-complete-separation.sh, fixed the same way both times). The main
# session (no agent_id) is untouched by this gate.
#
# Non-goal (same accepted scope as irrecoverable.sh / agent-recursion-guard.sh):
# this is a coarse command-pattern match, not an adversarial sandbox. It
# does not attempt to defeat deliberate quote-splitting, variable
# indirection, or command-substitution obfuscation of the literal word
# "git" itself -- same non-goal those two gates already carry for
# "claude"/"rm"/etc. No env-var bypass -- this enforces the harness's own
# concurrent-dispatch architecture, not a situational human judgment call,
# same posture as the two sibling gates.
set -uo pipefail

# Portability guard (#93): announced fail-open when python3 is missing.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — subagent-git-guard gate cannot run; allowing (install python3 to restore the subagent git-guard rule)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, re, sys

try:
    d = json.load(sys.stdin)
except Exception as e:
    # Fail-safe = ALLOW. A parse error must not stall every subagent Bash
    # call -- same choice as agent-recursion-guard.sh / task-complete-separation.sh.
    print(f"[mh:gate] subagent-git-guard: unparseable stdin, allowing ({e})", file=sys.stderr)
    sys.exit(0)

if not isinstance(d, dict):
    print("[mh:gate] subagent-git-guard: non-object payload, allowing", file=sys.stderr)
    sys.exit(0)

if d.get("tool_name") != "Bash":
    sys.exit(0)

# agent_id is present ONLY when the hook fires inside a subagent call.
# Absent => main session => untouched by this gate.
agent_id = d.get("agent_id")
if not agent_id:
    sys.exit(0)

ti = d.get("tool_input")
cmd = ti.get("command") if isinstance(ti, dict) else None
if not isinstance(cmd, str):
    sys.exit(0)

def clip(s):
    # Same log-injection guard as agent-recursion-guard.sh: strip
    # non-printable bytes and cap length so a crafted command string cannot
    # forge or erase a preceding "[mh:gate] ..." line.
    s = re.sub(r"[^\x20-\x7e]", "?", str(s))
    return s[:120]

agent_type = clip(d.get("agent_type") or "unknown")

# Anchor: "git" must sit right at a real command-start position (string
# start, |;&(, &&, ||, or a VAR=val prefix chain, optionally after a path
# like /usr/bin/git) -- same shape as agent-recursion-guard.sh _ANCHOR_RE.
# This is what a real invocation always looks like, and what a quoted
# commit message / grep pattern / echo string almost never does: a quote
# character sitting right before "git" is not itself an anchor char, so
# `grep -r "git reset" docs/` and `git commit -m "explain git stash here"`
# never anchor a match on that second occurrence at all.
_ANCHOR_RE = re.compile(
    r"(?:^|[|;&(]|&&|\|\|)\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*/)?git\b"
)
# Only the three verbs irrecoverable.sh does not already cover
# unconditionally (see header comment): stash, reset, clean. checkout and
# restore are deliberately absent here -- irrecoverable.sh already denies
# their destructive forms for every session, main included.
_DENY_SUBCMD_RE = re.compile(r"\A\s+(stash|reset|clean)\b")

def _violation(cmd):
    for m in _ANCHOR_RE.finditer(cmd):
        dm = _DENY_SUBCMD_RE.match(cmd[m.end():])
        if dm:
            return dm.group(1)
    return None

hit = _violation(cmd)
if hit:
    print(f"[mh:gate] BLOCKED: subagent ({agent_type}) may not run `git {hit}` "
          f"(command: {clip(cmd)!r}) -- no repo-wide git in a concurrent wave "
          f"(skills/workflow/orchestrate/f9-template.md, \"No repo-wide git in a "
          f"concurrent wave\"); scope every git command to files you own. "
          f"(git checkout -- / git restore are already denied unconditionally, "
          f"for every session, by gate:bash:irrecoverable when they would "
          f"discard working-tree changes -- not this gate'"'"'s job.)", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
'
exit $?
