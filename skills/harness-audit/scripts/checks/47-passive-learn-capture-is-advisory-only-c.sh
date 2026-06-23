# 47. Passive learn-capture is advisory-only + confidence-never-gates (ADR 0002
# addendum). Extends #34's pattern to the computational-FB capture path. The
# learn-capture hook must NEVER emit a permissionDecision (it journals + queues,
# never gates SessionEnd), and NEITHER the hook NOR skills/learn/SKILL.md may ever
# compare a confidence value against a threshold to trigger an action — that would
# be ECC's model-as-gate, which the addendum forbids (confidence is ordering-only).
# Strip full-line comments first (a comment NAMING the rule is fine). Hermetic:
# each leg skips cleanly if its file is absent.
LC_HOOK="$CLAUDE_DIR/hooks/session/learn-capture.sh"
LEARN_SKILL="$CLAUDE_DIR/skills/learn/SKILL.md"
if [ -f "$LC_HOOK" ]; then
  if grep -vE '^[[:space:]]*#' "$LC_HOOK" 2>/dev/null | grep -qE 'permissionDecision|hook_decision|kbg_permission_decision'; then
    crit "autonomy invariant: learn-capture.sh emits a permissionDecision — passive capture must journal/queue, never gate (ADR 0002 addendum; same class as #34)"
  fi
fi
for _f in "$LC_HOOK" "$LEARN_SKILL"; do
  [ -f "$_f" ] || continue
  if grep -vE '^[[:space:]]*#' "$_f" 2>/dev/null | grep -qE 'confidence *(>=|>|-ge|-gt) *0\.[0-9]'; then
    crit "autonomy invariant: '${_f#"$CLAUDE_DIR"/}' gates on a confidence threshold — confidence is an ORDERING signal only, never an action trigger (ADR 0002 addendum; CANDIDATE-SCHEMA.md NON-NEGOTIABLE)"
  fi
done
# 47b. L4 auto-keep writer (design §6, #28): confidence may ORDER an auto-keep only
# under KBG_AUTONOMY=1 (the writer is autonomy_on-gated), and the writer must NEVER
# compare confidence itself (it consumes the already-sorted read-candidates list) +
# must shell NO git push / gh (local-only — Gate 2 holds the batch, not the writer).
# Positive assertions: CRIT UNLESS the writer is clean — removing the assertion re-
# trips (test-ch-l3.sh injects a comparison / push-verb into a fixture copy + asserts
# the CRIT). Same commit as the writer (#27) — no neither-blocked-nor-caught window.
# Hermetic: skips if the writer is absent.
LC_WRITER="$CLAUDE_DIR/scripts/l4/l4-auto-keep.py"
if [ -f "$LC_WRITER" ]; then
  if grep -vE '^[[:space:]]*#' "$LC_WRITER" 2>/dev/null | grep -qE 'confidence[[:space:]]*(>=|>|<|<=|==|!=|-ge|-gt|-le|-lt|-eq|-ne)[[:space:]]*0\.[0-9]'; then
    crit "autonomy invariant: l4-auto-keep.py compares confidence against a threshold — confidence may ORDER (via the upstream sort) only, never GATE (design §6, #28 blocker-A; CANDIDATE-SCHEMA.md NON-NEGOTIABLE)"
  fi
  if grep -vE '^[[:space:]]*#' "$LC_WRITER" 2>/dev/null | grep -qE '(^|[[:space:];&|`])git[[:space:]]+push|["'"'"']push["'"'"']|(^|[[:space:];&|`])gh[[:space:]]|["'"'"']gh["'"'"']'; then
    crit "autonomy invariant: l4-auto-keep.py shells a git push / gh — the writer is LOCAL-ONLY; Gate 2 holds the batch, the writer never ships (design §6, #28 blocker-C)"
  fi
fi

