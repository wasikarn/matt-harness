# 40. Fan-out band single-source — the F8.4 floor (3) and F8.5 cap (5) are
# enforced in TWO independent places: scripts/orchestrate-dispatch.py
# (DEFAULT_MIN/MAX_PER_WAVE constants, clamps emitted waves) and
# scripts/plan_linter/core.py (a literal `count < N or count > M` on the
# ## Team Members roster). Both encode the same doctrine band but neither reads
# the other, so a doctrine change to the band could update one enforcer and not
# the other → two gates disagreeing silently. Extract the numbers from each and
# assert equality. WARN. Hermetic: skips if either file is absent.
DISPATCH_PY="$CLAUDE_DIR/scripts/orchestrate-dispatch.py"
LINTER_PY="$CLAUDE_DIR/scripts/plan_linter/core.py"
if [ -f "$DISPATCH_PY" ] && [ -f "$LINTER_PY" ]; then
  _dmin=$(grep -oE 'DEFAULT_MIN_PER_WAVE = [0-9]+' "$DISPATCH_PY" | grep -oE '[0-9]+$' | head -1)
  _dmax=$(grep -oE 'DEFAULT_MAX_PER_WAVE = [0-9]+' "$DISPATCH_PY" | grep -oE '[0-9]+$' | head -1)
  _lmin=$(grep -oE 'count < [0-9]+' "$LINTER_PY" | grep -oE '[0-9]+' | head -1)
  _lmax=$(grep -oE 'count > [0-9]+' "$LINTER_PY" | grep -oE '[0-9]+' | head -1)
  if [ -n "$_dmin" ] && [ -n "$_dmax" ] && [ -n "$_lmin" ] && [ -n "$_lmax" ] \
     && { [ "$_dmin" != "$_lmin" ] || [ "$_dmax" != "$_lmax" ]; }; then
    warn "fan-out band drift: orchestrate-dispatch.py F8.4/F8.5 = ${_dmin}-${_dmax} but plan_linter/core.py enforces ${_lmin}-${_lmax} — both encode the same doctrine band and MUST agree"
  fi
fi

