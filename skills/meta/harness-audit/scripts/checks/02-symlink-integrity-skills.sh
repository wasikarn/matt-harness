#!/usr/bin/env bash
# 2. Symlink integrity — skills
#
# CI-safety (reproduced 2026-08-28 by an adversarial plan review: 0 CRIT
# locally vs 76 CRIT under an isolated $HOME simulating a fresh GitHub
# runner). This loop's per-component F1 CRIT depends on either a local
# ~/.claude symlink farm (dev-mode install) or the plugin cache
# ($PLUGIN_ACTIVE, set earlier in audit.sh) — a clean checkout with neither
# has genuinely no way to prove loadability, which is a different fact than
# "every skill is missing." Distinguish by whether $HOME/.claude/skills
# exists AT ALL: if it does, this machine is using symlink-mode and a
# missing individual symlink is still a real, per-component gap (unchanged
# behavior below). If it does not, AND $PLUGIN_ACTIVE=0, neither delivery
# mechanism is configured here at all — downgrade to one aggregated WARN
# instead of one CRIT per skill, and skip the loop.
#
# Bootstrap (GH #204, #211): the plugin cache is built from committed state, so a skill added after
# the commit the cache was built from cannot be in it yet, and this repo denies --no-verify and does
# not symlink plugin skills. A skill whose SKILL.md is absent from the base commit is reported as
# INFO instead. Base, first hit wins: HARNESS_AUDIT_BASE_REF; the gitCommitSha that
# installed_plugins.json records for the cache being audited; origin/develop. Fails closed (CRIT
# stays) unless CLAUDE_DIR is its own git toplevel and the base resolves, so fixtures and repos with
# no base get no exemption. A skill that is on the base commit but missing from the cache is a real
# gap and stays CRIT.
f1_cache_sha() {
  python3 - "$HOME/.claude/plugins/installed_plugins.json" "${PLUGIN_CACHE:-}" <<'PY' 2>/dev/null
import json, sys
try:
    plugins = json.load(open(sys.argv[1])).get("plugins", {})
except Exception:
    sys.exit(0)
want = sys.argv[2].rstrip("/")
for entries in plugins.values():
    for e in entries if isinstance(entries, list) else []:
        if want and str(e.get("installPath", "")).rstrip("/") == want and e.get("gitCommitSha"):
            print(e["gitCommitSha"])
            sys.exit(0)
PY
}
f1_base() {
  local sha
  if [ -n "${HARNESS_AUDIT_BASE_REF:-}" ]; then printf '%s' "$HARNESS_AUDIT_BASE_REF"; return; fi
  sha=$(f1_cache_sha)
  if [ -n "$sha" ] && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$CLAUDE_DIR" rev-parse --verify -q "$sha^{commit}" >/dev/null 2>&1; then
    printf '%s' "$sha"
  else
    printf '%s' origin/develop
  fi
}
f1_new_vs_base() {
  local dir="${1%/}" base="$F1_BASE" top rel
  top=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$CLAUDE_DIR" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$(cd -P "$CLAUDE_DIR" && pwd)" = "$(cd -P "$top" && pwd)" ] || return 1
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$CLAUDE_DIR" rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || return 1
  rel="${dir#"$CLAUDE_DIR"/}"
  # ls-tree exits 0 with empty output for an absent path but non-zero on a git error (missing
  # object in a shallow or partial clone); cat-file -e and rev-parse --verify both exit non-zero
  # for either, which would read an error as "absent" and fail open.
  local hit
  hit=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$CLAUDE_DIR" ls-tree --name-only "$base" -- "$rel/SKILL.md" 2>/dev/null) || return 1
  [ -z "$hit" ]
}
if [ "${PLUGIN_ACTIVE:-0}" -eq 0 ] && [ ! -d "$HOME/.claude/skills" ]; then
  warn "no plugin cache and no ~/.claude/skills symlink farm present — skill loadability unverified in this environment (expected on a clean CI checkout; not a per-skill finding)"
else
F1_BASE=$(f1_base)
for d in "$CLAUDE_DIR/skills"/*/ "$CLAUDE_DIR/skills"/*/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  # Skip self during bootstrap; skip _-prefixed scaffolds (not deployed skills —
  # install.sh applies the same `_*` rule so the two never disagree). Skip
  # *-workspace dirs too — skill-creator eval workspaces, gitignored under
  # .gitignore's own "Session / skill workspaces" section, never deployed.
  [ "$name" = "harness-audit" ] && continue
  case "$name" in _*|*-workspace) continue ;; esac
  # A directory under skills/ with no SKILL.md was never an invocable skill;
  # nothing here could load, so "not loadable" would be a false positive.
  [ -f "$d/SKILL.md" ] || continue
  # Skip upstream-tracked skills (Matt Pocock + gstack + ECC + etc.) — locked
  # in ~/.agents/.skill-lock.json. Editing them drifts the content hash and
  # corrupts the install. They are intentionally NOT symlinked to dotfiles.
  # SSOT: ~/.agents/.skill-lock.json, record in memory `project_skill_lock_ssot`.
  for locked in "${LOCKED_SKILLS[@]:-}"; do
    [ "$name" = "$locked" ] && continue 2
  done
  if [ ! -L "$HOME/.claude/skills/$name" ] && ! is_plugin_delivered skills "$name"; then
    if f1_new_vs_base "$d"; then
      info "skill '$name' is new vs ${F1_BASE}; not in the plugin cache until a bumped version is merged and installed"
    else
      crit "skill '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
    fi
  fi
done
fi

