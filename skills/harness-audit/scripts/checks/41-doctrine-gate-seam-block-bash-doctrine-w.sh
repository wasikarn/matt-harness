# 41. Doctrine gate seam — block-bash-doctrine-write.sh and doctrine-edit-gate.sh
# hardcode the SAME doctrine-file set in two encodings (block-bash a factored
# regex `(A|B|C)\.md|x\.json`; doctrine-edit a flat case-glob `A.md|B.md|…`),
# joined only by a "Keep aligned" comment with NO machine-check. block-bash
# exists SPECIFICALLY to close the Bash-redirect bypass around doctrine-edit-gate
# (which only catches the Edit/Write/MultiEdit tools), so if a doctrine file is
# added to the Edit/Write gate but not the Bash gate, the shell-redirect bypass
# silently REOPENS for that file. Normalize both to a sorted basename set and
# assert equality. Security-load-bearing → WARN (same class as #37/#40).
# Hermetic: skips if either gate is absent; warns loudly if either pattern can't
# be extracted (the gate format changed and this check has gone blind).
BBW="$CLAUDE_DIR/hooks/gates/block-bash-doctrine-write.sh"
DEG="$CLAUDE_DIR/hooks/gates/doctrine-edit-gate.sh"
if [ -f "$BBW" ] && [ -f "$DEG" ]; then
  # block-bash: the DOCTRINE_NAMES='…' regex. Strip the `NAME='`…`'` wrapper and
  # the regex escapes, then distribute the one parenthesized group's trailing
  # suffix `(A|B|C).md` → `A.md|B.md|C.md` via a portable sed branch-loop
  # (-e ':a' … -e 'ta' — BSD + GNU). Split on `|`, drop blanks, sort.
  _bbw=$(grep -E "^DOCTRINE_NAMES='" "$BBW" | head -1 \
    | sed -E "s/^DOCTRINE_NAMES='//; s/'.*$//; s/\\\\//g" \
    | sed -E -e ':a' \
             -e 's/\(([^|()]+)\|([^()]*)\)([^|]*)/\1\3|(\2)\3/' \
             -e 'ta' \
             -e 's/\(([^()]+)\)([^|]*)/\1\2/' \
    | tr '|' '\n' | sed '/^$/d' | sort -u)
  # doctrine-edit: the flat case-glob `  A.md|B.md|…)`. Pick the `.md`-bearing
  # case line, strip indent + trailing `)`, split on `|`, drop blanks, sort.
  _deg=$(grep -E '^[[:space:]]*[A-Za-z.][A-Za-z0-9.|_-]*\)[[:space:]]*$' "$DEG" \
    | grep -F '.md' | head -1 \
    | sed -E 's/^[[:space:]]*//; s/\)[[:space:]]*$//' \
    | tr '|' '\n' | sed '/^$/d' | sort -u)
  if [ -z "$_bbw" ] || [ -z "$_deg" ]; then
    warn "doctrine gate seam (audit #41) has gone BLIND — could not extract the doctrine-file set from block-bash-doctrine-write.sh and/or doctrine-edit-gate.sh; the gate format changed, re-point the extractors before trusting this check"
  elif [ "$_bbw" != "$_deg" ]; then
    # diff exits 1 when the sets differ (always, in this branch); `|| true`
    # keeps that expected non-zero from tripping `set -euo pipefail` before the
    # warn fires. (#37 shared this latent bug in a `_d=$(diff …)` assignment —
    # now also guarded. #38/#40 run their diffs in `if` conditions, which set -e
    # exempts, so they were never at risk.)
    _d=$(diff <(printf '%s\n' "$_bbw") <(printf '%s\n' "$_deg") | tr '\n' ' ' | cut -c1-280 || true)
    warn "doctrine gate seam DRIFT: block-bash-doctrine-write.sh and doctrine-edit-gate.sh protect DIFFERENT doctrine-file sets — the Bash-redirect bypass reopens for any file in one gate but not the other. diff (< block-bash, > doctrine-edit): $_d"
  fi
fi

