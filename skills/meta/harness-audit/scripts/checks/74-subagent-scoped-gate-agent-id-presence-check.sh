#!/usr/bin/env bash
# 74. Subagent-scoped gate agent_id presence-check invariant (harness gap-audit,
# 2026-09-20). Four gates key their entire subagent-only behavior on whether
# `agent_id` is PRESENT in the PreToolUse payload, never on whether it's
# truthy -- an empty-string or JSON-null agent_id is still a real subagent
# call and must still be gated. A truthiness check (`d.get("agent_id")` or a
# bare `if agent_id:`) silently skips the check for exactly that shape,
# reproduced live as a real bypass in irrecoverable.py (both
# `_nested_spawn` call sites) and subagent-git-guard.py before the 2026-09-20
# fix pass -- see docs/reference/operating-model.md's "three [now four]
# subagent-scoped gates, one posture" invariant. This makes that invariant
# mechanical instead of relying on remembering to check it by hand on every
# future edit to any of these four files.
#
# CRIT: any of the four files is missing the presence-check idiom
# (`"agent_id" in d` / `"agent_id" not in d`) entirely -- either the file was
# never fixed, or a future edit regressed it back to a truthiness gate
# without leaving the presence-check string anywhere in the file.
_AGENT_ID_GATE_FILES="irrecoverable.py subagent-git-guard.py subagent-spawn-guard.py task-complete-separation.py"
for _f in $_AGENT_ID_GATE_FILES; do
  _path="$CLAUDE_DIR/hooks/gates/$_f"
  if [ ! -f "$_path" ]; then
    crit "hooks/gates/$_f missing -- can't verify its agent_id presence-check invariant"
    continue
  fi
  # Comments AND triple-quoted strings stripped first (python3 tokenize, the
  # same tool sibling checks use; sed fallback drops # comments only when
  # python3 is absent) so a prose mention of the idiom in a docstring/comment
  # can't substitute for the real code check. A 2026-09-21 deep-audit found the
  # old `sed 's/#.*$//'` let a docstring-only file pass. Only TRIPLE-quoted
  # strings go: `"agent_id"` is itself a string token, stripping all strings
  # would delete the idiom. Matches are counted with `grep -o | wc -l`, not
  # `grep -c`, so several idioms on one line (or one joined line) each count.
  # grep WITHOUT -q, redirected instead: under this script's `set -o
  # pipefail`, grep -q's early-exit-on-first-match can SIGPIPE the still-
  # writing upstream, and pipefail then reports that SIGPIPE (141) as the
  # pipeline's status instead of grep's own 0 (live-reproduced while writing
  # this check against irrecoverable.py's own file).
  if command -v python3 >/dev/null 2>&1; then
    _code=$(python3 - "$_path" 2>/dev/null <<'PYEOF'
import io, sys, tokenize
src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
out = []
try:
    for t in tokenize.generate_tokens(io.StringIO(src).readline):
        if t.type == tokenize.COMMENT:
            continue
        if t.type == tokenize.STRING and t.string.lstrip("rbuRBUfF")[:3] in ('"""', "'" * 3):
            continue
        out.append("\n" if t.type in (tokenize.NEWLINE, tokenize.NL) else t.string)
except (tokenize.TokenError, SyntaxError):
    pass  # check 17 reports a file that doesn't tokenize; count what we got
print(" ".join(out))
PYEOF
)
  else
    _code=$(sed 's/#.*$//' "$_path" 2>/dev/null)
  fi
  _n=$(printf '%s\n' "$_code" | /usr/bin/grep -oE '"agent_id"[[:space:]]+(not[[:space:]]+)?in[[:space:]]+d\b' 2>/dev/null | wc -l | tr -d ' ') || _n=0  # grep exits 1 on zero matches; pipefail + set -e would abort the audit
  # irrecoverable.py has two _nested_spawn call sites (b561758c); both must
  # carry the idiom, so one match there means one site regressed.
  _need=1
  [ "$_f" = "irrecoverable.py" ] && _need=2
  if [ "${_n:-0}" -lt "$_need" ]; then
    crit "hooks/gates/$_f has $_n \"agent_id\" (not )in d presence-check(s) in code, need $_need -- may have regressed to a truthiness gate that skips an empty-string/null agent_id (see docs/reference/operating-model.md)"
  fi
done
unset _f _path _code _n _need _AGENT_ID_GATE_FILES
