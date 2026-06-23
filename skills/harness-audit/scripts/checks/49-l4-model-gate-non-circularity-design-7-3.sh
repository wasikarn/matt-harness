# 49. L4 model-gate non-circularity (design §7, #30). The quality-gate is the one
# inferential surface allowed inside an armed run, so it MUST be structurally fail-
# closed + read-only — do NOT rely on #45 (it guards reviewer-*agent* tools:, not a
# shell judge). Positive assertions over scripts/l4/l4-quality-gate.sh (CRIT UNLESS
# each holds — regressing one re-trips, tested in test-ch-l3.sh):
#   (a) read-only: the default judge command grants no Write/Edit (mutation tools);
#   (b) fail-closed: a missing/unparseable verdict resolves to rollback (the *) case);
#   (c) veto-only: a red gauntlet short-circuits before any model call (never red→green);
#   (d) veto-green: a NOT_GOOD verdict forces rollback.
# Presence: the gate + the trial allowlist exist. Cage-sync is covered by the
# scripts/l4/** anchor (#43d checks it bidirectionally) — the files live under it.
if [ -f "$ADR0004" ]; then
  QG="$CLAUDE_DIR/scripts/l4/l4-quality-gate.sh"
  QT="$CLAUDE_DIR/scripts/l4/l4-quality-trial.txt"
  [ -f "$QG" ] || crit "audit #49: scripts/l4/l4-quality-gate.sh missing — the L4 model-gate is absent (design §7, #29)"
  [ -f "$QT" ] || crit "audit #49: scripts/l4/l4-quality-trial.txt missing — the model-gate trial allowlist is absent (design §7, #29)"
  if [ -f "$QG" ]; then
    _qg=$(grep -vE '^[[:space:]]*#' "$QG" 2>/dev/null)
    _qbad=""
    printf '%s\n' "$_qg" | grep -qF 'RESULT" = "red"' || _qbad="$_qbad red-shortcircuit(never-bless-red)"
    printf '%s\n' "$_qg" | grep -qF '*NOT_GOOD*' || _qbad="$_qbad veto-green(NOT_GOOD)"
    printf '%s\n' "$_qg" | grep -qF -- '--allowedTools' || _qbad="$_qbad read-only-judge(--allowedTools)"
    printf '%s\n' "$_qg" | grep -qE '\*[^[:space:]]*\)' && printf '%s\n' "$_qg" | grep -qF 'rollback' || _qbad="$_qbad fail-closed-default(rollback)"
    # read-only: NO Write/Edit granted to the judge in active code.
    if printf '%s\n' "$_qg" | grep -qE 'Write|Edit'; then _qbad="$_qbad judge-grants-mutation(Write/Edit)"; fi
    [ -z "$_qbad" ] || crit "audit #49: l4-quality-gate.sh structural fail-closed/read-only regressed (missing:$_qbad) — design §7, #30. The model-gate must stay veto-only + fail-closed + read-only."
  fi
fi

