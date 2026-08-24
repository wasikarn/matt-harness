#!/usr/bin/env bash
# 16. BOUNDARY.md drift — committed capability map vs live fleet
# The map is a generated snapshot; if a skill/agent/hook is added or its
# description changes without regenerating, the canonical map goes stale.
BOUNDARY="$CLAUDE_DIR/BOUNDARY.md"
BOUNDARY_GEN="$CLAUDE_DIR/skills/inventory/scripts/inventory-boundary.sh"
if [ -f "$BOUNDARY" ] && [ -f "$BOUNDARY_GEN" ]; then
  _tmp_boundary=$(mktemp)
  if ( cd "$REPO_ROOT" && bash "$BOUNDARY_GEN" --repo-only ) > "$_tmp_boundary" 2>/dev/null; then
    # Ignore the volatile "_Generated:" timestamp line when comparing.
    if ! diff <(grep -v '^_Generated:' "$BOUNDARY") \
              <(grep -v '^_Generated:' "$_tmp_boundary") >/dev/null 2>&1; then
      warn "BOUNDARY.md stale vs repo fleet — regenerate: bash <matt-harness>/skills/inventory/scripts/inventory-boundary.sh --repo-only > <dotfiles>/claude/BOUNDARY.md  (substitute your matt-harness and dotfiles repo roots)"
    fi
  else
    warn "could not regenerate boundary map to check drift (inventory-boundary.sh failed)"
  fi
  rm -f "$_tmp_boundary"
else
  # Never silently no-op: a missing map or generator would otherwise make this
  # drift check invisible with zero signal (#80). Name whichever is absent.
  [ -f "$BOUNDARY" ] || warn "BOUNDARY.md missing ($BOUNDARY) — boundary-drift check cannot run"
  [ -f "$BOUNDARY_GEN" ] || warn "boundary generator missing ($BOUNDARY_GEN) — boundary-drift check cannot run"
fi

