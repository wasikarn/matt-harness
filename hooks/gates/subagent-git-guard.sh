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
# Corrected 2026-09-04: an independent verifier live-probed the first
# version and found two real gaps that were NOT the disclaimed non-goal
# below -- `git -C /repo stash` (and -c/--git-dir/--work-tree/--config-env/
# --no-pager/etc global flags, plus a `sudo`/`xargs` wrapper) walked past
# the old adjacent-to-"git" subcommand check entirely, and the anchor only
# matched absolute string offset 0 (no re.MULTILINE), so a `git reset` on
# its own line inside a multi-line Bash command string was never anchored.
# Both are now fixed: the anchor walks past a recognized git global flag
# set and an optional leading sudo/xargs wrapper before checking the
# subcommand verb (same technique irrecoverable.sh's own git global-flag
# walk uses, adapted to this gate's regex shape), and the anchor runs with
# re.MULTILINE so each line's own start anchors independently.
#
# The same pass also fixed a false positive: the anchor used to fire on
# any `;`/`&`/`|`/`(` character regardless of whether it sat inside a
# quoted argument, so `git commit -m "fix; git reset was wrong"` wrongly
# denied on the quoted "git reset". The anchor search now runs against a
# quote-masked copy of the command (single-quote spans literal,
# double-quote spans backslash-escape-aware, same as real bash) -- a
# separator character inside a quoted span is never a real anchor.
#
# Non-goal: still a coarse command-pattern match, not an adversarial
# sandbox. What it does NOT attempt to defeat is deliberate
# quote-splitting, variable indirection, or command-substitution
# obfuscation of the literal word "git" itself (e.g. `g''it stash`,
# `$(echo git) stash`) -- same non-goal those two sibling gates already
# carry for "claude"/"rm"/etc. Ordinary global flags, a bare sudo/xargs
# wrapper, and quoted-argument punctuation are NOT in that non-goal
# anymore -- they're handled above. One more non-goal the re.MULTILINE fix
# introduces: a heredoc BODY line that happens to start with "git
# stash"/"reset"/"clean" as plain text (not a real shell command) now
# anchors and denies too -- same over-block direction the anchor already
# accepts for prose in general, not attempting to parse heredoc
# boundaries. No env-var bypass -- this enforces the harness's own
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

# Quote-aware masking (2026-09-04 fix): replace every character inside a
# single- or double-quoted span, including the quote marks, with a
# placeholder that cannot match a separator character, git, or a flag --
# output is the same length as input, so every match position below still
# lines up with the ORIGINAL cmd string for clip()/reporting. Single-quote
# spans are literal; double-quote spans respect backslash-escaping, same
# as real bash. Uses chr() for the quote characters rather than literal
# ones, since this whole block sits inside a bash single-quoted python3 -c
# wrapper -- same reason agent-recursion-guard.sh does the same for its
# own quote handling.
# ponytail: no handling for a backslash-escaped quote OUTSIDE a quoted
# span (real bash lets a leading backslash make the next quote char
# literal there too) -- no case in the test suite for this gate needs it;
# add a one-char lookback if a real false positive/negative traces to it.
_SQ = chr(39)
_DQ = chr(34)

def _mask_quotes(s):
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == _SQ:
            out.append(" "); i += 1
            while i < n and s[i] != _SQ:
                out.append("Q"); i += 1
            if i < n:
                out.append(" "); i += 1
        elif c == _DQ:
            out.append(" "); i += 1
            while i < n and s[i] != _DQ:
                if s[i] == "\\" and i + 1 < n:
                    out.append("Q"); out.append("Q"); i += 2
                else:
                    out.append("Q"); i += 1
            if i < n:
                out.append(" "); i += 1
        else:
            out.append(c); i += 1
    return "".join(out)

masked = _mask_quotes(cmd)

# Anchor: "git" must sit right at a real command-start position (string
# start, |;&(, &&, ||, an optional VAR=val prefix chain, an optional
# leading sudo/xargs wrapper, or a path like /usr/bin/git) -- same shape
# as agent-recursion-guard.sh _ANCHOR_RE, extended 2026-09-04 for two gaps
# a verifier found: `sudo git stash` / `xargs git stash` used to slip
# through with no anchor at all, and this now runs with re.MULTILINE so a
# `git reset` at the start of its own line inside a multi-line Bash
# command anchors too, not just absolute string offset 0. Runs against the
# quote-masked string above, so a quote character sitting right before
# "git", or a separator character sitting inside a quoted span, is never
# itself an anchor: `grep -r "git reset" docs/`, `git commit -m "explain
# git stash here"`, and `git commit -m "fix; git reset was wrong"` never
# anchor a match on the quoted occurrence at all.
_ANCHOR_RE = re.compile(
    r"(?:^|[|;&(]|&&|\|\|)\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*"
    r"(?:sudo\s+(?:\S+\s+)*|xargs\s+(?:\S+\s+)*)?(?:\S*/)?git\b",
    re.MULTILINE,
)
# Only the three verbs irrecoverable.sh does not already cover
# unconditionally (see header comment): stash, reset, clean. checkout and
# restore are deliberately absent here -- irrecoverable.sh already denies
# their destructive forms for every session, main included.
_DENY_SUBCMD_RE = re.compile(r"\A\s+(stash|reset|clean)\b")

# Known git global flags this gate walks past before checking the
# subcommand -- fixes the bypass a verifier found: `git -C /repo stash`,
# `git --no-pager clean -d`, `git -c core.x=y reset`, and `git
# --git-dir=.git stash` used to land the deny check on sub="-C" (etc)
# instead of the real subcommand and silently miss it. Same technique
# irrecoverable.sh already uses for its own git global-flag walk (see its
# "Walk past leading global flags" comment), adapted here to a regex-tail
# shape instead of full pre-tokenization.
_GIT_VALUE_GLOBALS = ("-C", "-c", "--git-dir", "--work-tree", "--config-env")

def _skip_git_globals(tail):
    # tail starts right at the end of the "git" anchor match, on the
    # quote-masked string, so a quoted flag value cannot desync the walk.
    # Returns the suffix starting at the first non-flag token (the
    # subcommand), leading whitespace intact so _DENY_SUBCMD_RE \A\s+
    # still matches it.
    i = 0
    while True:
        m = re.match(r"\s+(\S+)", tail[i:])
        if not m:
            return tail[i:]
        tok = m.group(1)
        if not tok.startswith("-"):
            return tail[i:]
        if tok in _GIT_VALUE_GLOBALS:
            i += m.end()
            m2 = re.match(r"\s+\S+", tail[i:])
            if m2:
                i += m2.end()
            continue
        i += m.end()  # any other flag, bare or combined: --git-dir=X, --no-pager, -p, ...

def _violation(masked_cmd):
    for m in _ANCHOR_RE.finditer(masked_cmd):
        dm = _DENY_SUBCMD_RE.match(_skip_git_globals(masked_cmd[m.end():]))
        if dm:
            return dm.group(1)
    return None

hit = _violation(masked)
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
