#!/usr/bin/env bash
# 58. ship-merge scored-gate threshold integrity — the pass threshold ("70") and
# the Critical-findings weight ("30") must hold the margin invariant
# D*100/(C+D) < T, or the automation-bias guard's deliberate 0 on Critical
# findings can reach the pass threshold on deterministic signals alone (CRIT).
#
# The known gap (docs/reference/ship-merge-scored-gate-margin.md:65-73, filed
# 2026-07-29, open): the shared "70" pass threshold can be edited directly
# (70->60) to reach the same bypass as editing the table weights, WITHOUT
# re-checking the margin D >= (7/3)*C. Lowering Critical's own weight alone
# (30->23) also defeats it with D unchanged. This check is the deterministic
# backstop: it reads C, D, T from commands/ship-merge.md itself and asserts the
# invariant holds. A consistent change (weights + threshold moved together such
# that the invariant still holds) passes; a silent threshold drop OR a weight
# drop that breaks the invariant CRITs — forcing the documented margin
# re-derivation. Mirrors check 57's bidirectional shape: the invariant is the
# real check, not a fixed literal.
# ship-merge.md may live flat or directory-form — mirror check 44's own
# path resolution (both are valid per docs/command-authoring-conventions.md).
_sm=""
[ -f "$CLAUDE_DIR/commands/ship-merge.md" ] && _sm="$CLAUDE_DIR/commands/ship-merge.md"
[ -f "$CLAUDE_DIR/commands/ship-merge/COMMAND.md" ] && _sm="$CLAUDE_DIR/commands/ship-merge/COMMAND.md"
if [ ! -f "$_sm" ]; then
  crit "ship-merge command not found at commands/ship-merge.md or commands/ship-merge/COMMAND.md — the scored merge gate is missing"
else
  # Parse the criterion weights from the scored-gate table rows. Each row is
  # `| <name> | <weight> | <measures> |`. Extract the weight (first integer in
  # the weight column). Fail-closed if any weight is unparseable.
  _w() { /usr/bin/grep -E "\| $1 \|" "$_sm" | head -1 | sed -E 's/.*\| ([0-9]+) \|.*/\1/'; }
  C=$(_w "Critical findings"); ci=$(_w "CI status"); fr=$(_w "Review freshness"); cv=$(_w "Review coverage")
  # Threshold T: the integer before "threshold" in the gate line ("below the 70
  # threshold"). Floor is 40 (separate, not the invariant).
  T=$(/usr/bin/grep -Eo '[0-9]+ threshold' "$_sm" | head -1 | /usr/bin/grep -Eo '^[0-9]+')

  _bad=0
  case "$C"  in ''|*[!0-9]*) _bad=1;; esac
  case "$ci" in ''|*[!0-9]*) _bad=1;; esac
  case "$fr" in ''|*[!0-9]*) _bad=1;; esac
  case "$cv" in ''|*[!0-9]*) _bad=1;; esac
  case "$T"  in ''|*[!0-9]*) _bad=1;; esac

  if [ "$_bad" = "1" ]; then
    crit "ship-merge.md: scored-gate table or threshold unparseable (C=$C ci=$ci fr=$fr cv=$cv T=$T) — cannot re-derive the margin invariant; the gate's weights/threshold were edited in a way that breaks the contract shape. Re-derive D*100/(C+D) < T per docs/reference/ship-merge-scored-gate-margin.md"
  else
    D=$((ci + fr + cv))
    # Margin invariant: the automation-bias 0 on Critical (weight C kept in the
    # denominator) can reach the pass threshold T on deterministic signals alone
    # iff D*100/(C+D) >= T. It MUST stay below T or the self-tiered-sensitive-
    # review bypass reopens (a deliberate 0 that can pass is no longer a brake).
    # bash integer arithmetic: D*100 < T*(C+D) => safe.
    _lhs=$((D * 100))
    _rhs=$((T * (C + D)))
    if [ "$_lhs" -ge "$_rhs" ]; then
      crit "ship-merge.md: margin invariant BROKEN — D*100/(C+D) >= T with C(Critical)=$C D(CI+freshness+coverage)=$D T=$T. The automation-bias guard's deliberate 0 on Critical findings can now reach the $T pass threshold on deterministic signals alone. The scored gate's self-review brake is gone. Re-derive the margin per docs/reference/ship-merge-scored-gate-margin.md: raise T, raise C, or lower D so D*100/(C+D) < T holds again."
    fi
  fi
fi
