#!/usr/bin/env bash
# 57. Convergence merge-gate contract — the raw `gh pr merge` deny-gate must be
# registered in hooks.json AND its script must still carry the fast-path, the
# `clean` read, and the sys.exit(2) deny (CRIT).
#
# The convergence gate has two layers: advisory (review-pr-finish Phase 7 footer) and
# computational (ship-merge's scored gate reads force_human). The decisive gap
# found 2026-08-13 in session 6e7c3bed: ship-merge is disable-model-invocation,
# so the model merges via raw `gh pr merge`, which had NO gate — the verifier
# was never connected to the one-way door actually used. convergence-merge-
# gate.sh closes that: a PreToolUse:Bash deny-gate that blocks a raw `gh pr
# merge` on a non-clean review state (clean != true), redirecting to ship-merge.
#
# If the registration is silently removed from hooks.json, or the gate script
# is neutered (fast-path dropped → python cold-start on every command AND no
# merge detection; `clean` read dropped → no decision basis; sys.exit(2)
# dropped → no deny), the bypass reopens with no signal. Three load-bearing
# parts, all asserted — a one-sided grep (registration-only) would pass while
# the script silently stopped denying. Mirrors check 56's verifier-contract
# shape: the gate is load-bearing in two files, so both are asserted.
_h="$CLAUDE_DIR/hooks/hooks.json"
_g="$CLAUDE_DIR/hooks/gates/convergence-merge-gate.sh"
if [ -f "$_h" ]; then
  /usr/bin/grep -q 'convergence-merge-gate.sh' "$_h" || \
    crit "hooks.json: convergence-merge-gate.sh registration lost — the raw \`gh pr merge\` deny-gate is no longer wired as PreToolUse:Bash; a non-clean review can merge via raw gh with no computational backstop (the 6e7c3bed 12-round bypass reopens)"
else
  crit "hooks.json: not found at $_h — the hook registry is missing entirely"
fi
if [ -f "$_g" ]; then
  # Widened 2026-08-15 (issue #49): the fast-path condition changed from a
  # contiguous `"pr merge"` glob to a `gh` AND `merge` presence check (order-
  # independent), so a merge hidden behind mid-command variable indirection
  # (`gh pr $M 42` where `M=merge`) still reaches the python slow path. This
  # assertion must track the ACTUAL gating expression, not just a substring
  # that happens to survive in a comment -- a real neuter (e.g. deleting the
  # `[[ ... ]]` condition entirely) must fail this check.
  /usr/bin/grep -q '\*gh\*' "$_g" && /usr/bin/grep -q '\*merge\*' "$_g" || \
    crit "convergence-merge-gate.sh: fast-path lost its gh/merge candidate check — the bash fast-path no longer catches merge commands, so every non-merge command may spawn python (latency) AND merge commands may bypass the python detection"
  /usr/bin/grep -q 's\.get("clean")' "$_g" || \
    crit "convergence-merge-gate.sh: lost the \`clean\` field read — the gate no longer reads the review state's clean verdict, so it cannot decide allow-vs-deny; it degrades to unconditional allow or unconditional deny"
  /usr/bin/grep -q 'sys.exit(2)' "$_g" || \
    crit "convergence-merge-gate.sh: lost the sys.exit(2) deny — the gate can no longer block a non-clean merge; the PreToolUse deny protocol is broken"
else
  crit "convergence-merge-gate.sh: not found at $_g — the merge-path deny-gate is missing entirely (the 6e7c3bed 12-round bypass reopens)"
fi
