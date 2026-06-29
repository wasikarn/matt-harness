# 29. Gate↔evidence separation (C1 evidence-journal invariant) — a hook that
# emits a permissionDecision (hook_decision) must NOT also call journal_append
# in the same file. Gate hooks decide; audit hooks journal. hook_decision exits
# 0, so any journal_append alongside it is either dead code or a decision path
# that journals before it decides — both wrong. See claude/hooks/JOURNAL-SCHEMA.md.
# Skip _*.sh libraries: _lib.sh DEFINES both functions and is not itself a hook.
for f in "$CLAUDE_DIR/hooks"/**/*.sh; do
  [ -f "$f" ] || continue
  case "${f#"$CLAUDE_DIR"/hooks/}" in tests/*|*__pycache__*) continue;; esac
  name=$(basename "$f")
  case "$name" in _*.sh) continue;; esac
  if grep -qw 'journal_append' "$f" && grep -qw 'hook_decision' "$f"; then
    crit "hook '$name' calls BOTH journal_append and hook_decision — gate hooks decide, audit hooks journal; separate them (JOURNAL-SCHEMA.md)"
  fi
done

