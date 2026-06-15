#!/usr/bin/env bash
# audit.sh — automated health check for the custom Claude Code ecosystem.
# Usage: bash audit.sh [<repo-root>] [--plugin-cache <path>]
# Exit code = number of findings (0 = clean).
set -uo pipefail

# Parse args. Positional [<repo-root>] first; optional --plugin-cache <path>
# second. Keep backward-compat: a single arg is treated as repo-root (the old
# call shape `bash audit.sh <repo>` still works).
REPO_ROOT=""
PLUGIN_CACHE_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-cache) PLUGIN_CACHE_ARG="${2:-}"; shift 2 ;;
    --plugin-cache=*) PLUGIN_CACHE_ARG="${1#--plugin-cache=}"; shift ;;
    *) [ -z "$REPO_ROOT" ] && REPO_ROOT="$1"; shift ;;
  esac
done
REPO_ROOT="${REPO_ROOT:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
# Layout: dotfiles nests the harness under claude/; the extracted kbg-harness
# plugin repo is flat (agents/, skills/, … at the root). Resolve CLAUDE_DIR to
# whichever holds the fleet so one audit.sh serves both checkouts.
if [ -d "$REPO_ROOT/claude" ]; then
  CLAUDE_DIR="$REPO_ROOT/claude"
else
  CLAUDE_DIR="$REPO_ROOT"
fi
SETTINGS="$CLAUDE_DIR/settings.json"
MEMORY_DIR="${REPO_ROOT//claude/}/.claude/projects/$(echo "$REPO_ROOT" | sed 's|/|_|g')/memory"

# Shared frontmatter helpers (sourced, not executed). Same `_lib` is used by
# inventory.sh / inventory-boundary.sh — see claude/skills/_lib/fm.sh for the
# full surface (fm_get, fm_has, fm_in_fm_section, fm_hook_desc,
# SKIP_SCAFFOLD_GLOB).
# shellcheck source=../../_lib/fm.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../_lib/fm.sh"

# Fail loud (Rule 12): if the resolved root holds none of the fleet dirs, root
# resolution failed — error out instead of a false-clean "0 artifacts" pass. A
# post-extraction dotfiles root legitimately has only hooks/; that still counts.
if [ ! -d "$CLAUDE_DIR/agents" ] && [ ! -d "$CLAUDE_DIR/skills" ] && \
   [ ! -d "$CLAUDE_DIR/commands" ] && [ ! -d "$CLAUDE_DIR/hooks" ]; then
  echo "FATAL: no harness fleet (agents/skills/commands/hooks) under: $CLAUDE_DIR" >&2
  echo "Pass the repo root explicitly: bash audit.sh <repo-root>" >&2
  exit 1
fi

CRIT_COUNT=0
WARN_COUNT=0
INFO_COUNT=0

# Locked skills = upstream-tracked installs in ~/.agents/.skill-lock.json
# (Matt Pocock, gstack, ECC, etc. — agent system installs + pins by content
# hash). Editing them in either ~/.claude/skills/<name> or ~/.agents/skills/<name>
# would drift the hash and corrupt the install. Symlink F1 is therefore
# silenced for these names. SSOT record: memory `project_skill_lock_ssot`.
LOCK_FILE="$HOME/.agents/.skill-lock.json"
LOCKED_SKILLS=()
if [ -f "$LOCK_FILE" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r s; do LOCKED_SKILLS+=("$s"); done < <(jq -r '.skills | keys[]' "$LOCK_FILE")
fi

# Plugin delivery (kbg-cutover 2026-06-11). The kbg@kobig plugin installs
# agents/skills/commands/hooks/output-styles into the user-scope plugin cache
# (default ~/.claude/plugins/cache/kobig/kbg/<version>/) and Claude Code loads
# them from there at runtime — NO symlink into ~/.claude/ is created. Without
# this awareness, F1 ("not symlinked to ~/.claude/…") fires on every
# plugin-delivered component as a false positive (62 CRITs on kbg-harness).
# --plugin-cache <path> overrides the default for testing (see tests/fixtures/).
# Resolve to the latest installed version of the kbg plugin in the cache,
# so a version bump (e.g. 0.1.0 -> 0.1.1 -> 0.1.2) doesn't silently disable
# F1 plugin-aware bypass. PLUGIN_CACHE_ARG still wins for explicit override.
if [ -z "$PLUGIN_CACHE_ARG" ]; then
  _KBG_CACHE_DIR="$HOME/.claude/plugins/cache/kobig/kbg"
  if [ -d "$_KBG_CACHE_DIR" ]; then
    _LATEST=$(ls -1 "$_KBG_CACHE_DIR" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    if [ -n "$_LATEST" ]; then
      PLUGIN_CACHE="$_KBG_CACHE_DIR/$_LATEST"
    else
      PLUGIN_CACHE="${_KBG_CACHE_DIR}/0.1.0"  # fallback for empty/missing cache
    fi
  else
    PLUGIN_CACHE="${_KBG_CACHE_DIR}/0.1.0"  # fallback when no cache dir
  fi
else
  PLUGIN_CACHE="$PLUGIN_CACHE_ARG"
fi
unset _KBG_CACHE_DIR _LATEST
PLUGIN_ACTIVE=0
if [ -d "$PLUGIN_CACHE/agents" ] || [ -d "$PLUGIN_CACHE/skills" ] || \
   [ -d "$PLUGIN_CACHE/commands" ] || [ -d "$PLUGIN_CACHE/hooks" ] || \
   [ -d "$PLUGIN_CACHE/output-styles" ]; then
  PLUGIN_ACTIVE=1
fi
# is_plugin_delivered <kind> <name> — returns 0 if a component named <name>
# of kind <kind> (skills|agents|commands|hooks|output-styles) is present in
# the plugin cache. Kinds map to cache subdirs: skills/<name>/SKILL.md,
# agents/<name>.md, commands/<name>.md, hooks/<name>, output-styles/<name>.md.
# Skills: a skill is a directory containing SKILL.md, so test the dir+file.
# Hooks: a hook is a single file (.sh or .py), so test the file directly.
# Agents/commands/output-styles: a single .md file.
is_plugin_delivered() {
  local kind="$1"
  local name="$2"
  case "$kind" in
    skills)        [ -f "$PLUGIN_CACHE/skills/$name/SKILL.md" ] ;;
    agents)        [ -f "$PLUGIN_CACHE/agents/$name.md" ] ;;
    commands)      [ -f "$PLUGIN_CACHE/commands/$name.md" ] ;;
    hooks)         [ -f "$PLUGIN_CACHE/hooks/$name" ] ;;
    output-styles) [ -f "$PLUGIN_CACHE/output-styles/$name.md" ] ;;
    *) return 1 ;;
  esac
}

id_counter=1
next_id() {
  local prefix="$1"
  local id
  id=$(printf "%s%d" "$prefix" "$id_counter")
  ((id_counter++))
  echo "$id"
}

crit() { local i=$(next_id F); echo "  CRIT $i: $1"; ((CRIT_COUNT++)); }
warn() { local i=$(next_id W); echo "  WARN $i: $1"; ((WARN_COUNT++)); }
info() { local i=$(next_id I); echo "  INFO $i: $1"; ((INFO_COUNT++)); }

# ── helpers (fm_get / fm_has / SKIP_SCAFFOLD_GLOB come from _lib/fm.sh) ──

# ── main ─────────────────────────────────────────────────────────────

echo "=== Skill Audit Report ==="
echo "Root: $REPO_ROOT"

# 1. Fleet count
AGENTS=$(ls "$CLAUDE_DIR/agents"/*.md 2>/dev/null | wc -l | tr -d ' ')
SKILLS=$(ls -d "$CLAUDE_DIR/skills"/[!_]*/ 2>/dev/null | wc -l | tr -d ' ')  # [!_]*/ skips _-prefixed scaffolds (e.g. _template) — not real fleet
COMMANDS=$(ls "$CLAUDE_DIR/commands"/*.md 2>/dev/null | wc -l | tr -d ' ')
HOOKS=$(ls "$CLAUDE_DIR/hooks"/*.sh "$CLAUDE_DIR/hooks"/*.py 2>/dev/null | wc -l | tr -d ' ')
echo "Fleet: $AGENTS agents, $SKILLS skills, $COMMANDS commands, $HOOKS hooks"
if [ "$PLUGIN_ACTIVE" -eq 1 ]; then
  info "Plugin cache detected at $PLUGIN_CACHE — F1 treats plugin-delivered components as loadable"
fi
echo ""

# 2. Symlink integrity — skills
for d in "$CLAUDE_DIR/skills"/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  # Skip self during bootstrap; skip _-prefixed scaffolds (not deployed skills —
  # install.sh applies the same `_*` rule so the two never disagree).
  [ "$name" = "harness-audit" ] && continue
  case "$name" in _*) continue ;; esac
  # Skip upstream-tracked skills (Matt Pocock + gstack + ECC + etc.) — locked
  # in ~/.agents/.skill-lock.json. Editing them drifts the content hash and
  # corrupts the install. They are intentionally NOT symlinked to dotfiles.
  # SSOT: ~/.agents/.skill-lock.json, record in memory `project_skill_lock_ssot`.
  for locked in "${LOCKED_SKILLS[@]:-}"; do
    [ "$name" = "$locked" ] && continue 2
  done
  if [ ! -L "$HOME/.claude/skills/$name" ] && ! is_plugin_delivered skills "$name"; then
    crit "skill '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
  fi
done

# 3. Symlink integrity — hooks
for f in "$CLAUDE_DIR/hooks"/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  [ "$name" = "__pycache__" ] && continue
  # Skip hook libraries (sourced by hooks, not registered as hooks themselves).
  # install.sh's *.{sh,py} glob WILL symlink these so hooks can `source` them
  # at runtime via `$(dirname "$0")/_lib.sh` — but the audit shouldn't expect
  # them in settings.json. Mirrors the _* scaffold rule used in skills/.
  # *.md = co-located docs (JOURNAL-SCHEMA.md, the evidence-journal contract) —
  # not registrable hooks; install.sh's {sh,py} glob never symlinks them.
  # *.json = plugin hook registry (hooks/hooks.json), not a hook script.
  # *.bak = editor/backup residue (e.g. hooks.json.test.bak from a hook-test
  # session), not a real hook — should not be symlinked and not in F1.
  case "$name" in _*.sh|_*.py|*.md|*.json|*.bak) continue;; esac
  # Plugin-mode hooks are wired in hooks/hooks.json and resolved at runtime via
  # ${CLAUDE_PLUGIN_ROOT}; they are intentionally NOT symlinked into ~/.claude.
  # Distinguishing mark: present in hooks.json but absent from settings.json,
  # OR present in the kbg@kobig plugin cache (delivery model is plugin-enable,
  # not symlink-farm — see #2/#3b for the equivalent pattern on skills/agents/…).
  if grep -q "$name" "$CLAUDE_DIR/hooks/hooks.json" 2>/dev/null \
     && ! grep -q "$name" "$SETTINGS" 2>/dev/null; then continue; fi
  if is_plugin_delivered hooks "$name"; then continue; fi
  if [ ! -L "$HOME/.claude/hooks/$name" ]; then
    crit "hook '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
  fi
done

# 3b. Symlink integrity — agents and commands.
# Regression guard: 14 agents (and at least one command) were committed to the
# repo but never symlinked into ~/.claude/, so Claude Code could not load them.
# No check caught it because symlink integrity covered only skills and hooks.
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  if [ ! -L "$HOME/.claude/agents/$name" ] && ! is_plugin_delivered agents "${name%.md}"; then
    crit "agent '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
  fi
done
for f in "$CLAUDE_DIR/commands"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  if [ ! -L "$HOME/.claude/commands/$name" ] && ! is_plugin_delivered commands "${name%.md}"; then
    crit "command '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
  fi
done

# 3c. Symlink integrity — output-styles.
# Output styles ship as .md files in claude/output-styles/ and must symlink
# to ~/.claude/output-styles/<name>.md so Claude Code can apply them via
# /output-style. Same regression class as §3b (committed but not loadable).
for f in "$CLAUDE_DIR/output-styles"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  if [ ! -L "$HOME/.claude/output-styles/$name" ] && ! is_plugin_delivered output-styles "${name%.md}"; then
    crit "output-style '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
  fi
done

# 4. Frontmatter completeness — agents
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  if ! grep -q '^---' "$f"; then
    crit "agent '$name' missing frontmatter"
  fi
  if [ -z "$(fm_get "$f" "name" --block)" ]; then
    crit "agent '$name' missing name: in frontmatter"
  fi
  if [ -z "$(fm_get "$f" "description" --block)" ]; then
    crit "agent '$name' missing description: in frontmatter"
  fi
  # "Daisy" placeholder — exclude audit skill which documents this check — specific Anthropic upstream pattern
  if [ "$name" != "harness-audit" ] && grep -qi 'Daisy\|\\bdaisy\\b' "$f"; then
    warn "agent '$name' contains upstream 'Daisy' placeholder"
  fi
done

# 4b. Frontmatter completeness — output-styles.
# Output styles are loadable via /output-style <name>; missing frontmatter
# means the style is registered but not selectable. Symlink check (#3c)
# catches missing-symlink; this catches malformed-symlink.
for f in "$CLAUDE_DIR/output-styles"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  if ! grep -q '^---' "$f"; then
    crit "output-style '$name' missing frontmatter"
  fi
  if [ -z "$(fm_get "$f" "name" --block)" ]; then
    crit "output-style '$name' missing name: in frontmatter"
  fi
  if [ -z "$(fm_get "$f" "description" --block)" ]; then
    crit "output-style '$name' missing description: in frontmatter"
  fi
  # "Daisy" placeholder — same upstream pattern as agents/skills
  if grep -qi 'Daisy\|\\bdaisy\\b' "$f"; then
    warn "output-style '$name' contains upstream 'Daisy' placeholder"
  fi
done

# 5. Frontmatter completeness — skills
for f in "$CLAUDE_DIR/skills"/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac  # skip _-prefixed scaffolds (e.g. _template), per the _* convention
  name=$(basename "$(dirname "$f")")
  if ! grep -q '^---' "$f"; then
    crit "skill '$name' missing frontmatter"
  fi
  if [ -z "$(fm_get "$f" "name" --block)" ]; then
    crit "skill '$name' missing name: in frontmatter"
  fi
  if [ -z "$(fm_get "$f" "description" --block)" ]; then
    crit "skill '$name' missing description: in frontmatter"
  fi
  # "Daisy" placeholder — exclude audit skill which documents this check
  if [ "$name" != "harness-audit" ] && grep -qi 'Daisy\|\\bdaisy\\b' "$f"; then
    warn "skill '$name' contains upstream 'Daisy' placeholder"
  fi
  # "Don't use for" in description (skill pattern) — exclude self during bootstrap.
  # Name-only skills (description ≤ 20 chars) carry no routing text; skip routing checks.
  desc=$(fm_get "$f" "description" --block)
  desc_len=${#desc}
  if [ "$name" != "harness-audit" ] && [ "$desc_len" -gt 20 ]; then
    if ! echo "$desc" | grep -qiE "Don't use for|Do NOT use for|Do NOT trigger"; then
      warn "skill '$name' missing negation clause (e.g. 'Don't use for') in description"
    fi
    # Positive-side: trigger pattern (verb + scenario) — complement to negation check.
    # Bare-verb descriptions ("Loads the foo skill") auto-trigger on every prompt;
    # require a "when"-clause (Use when… / Trigger when… / ALWAYS trigger when… / Trigger on:)
    # to gate routing. Block-scalar descriptions ARE matched (fm_get --block returns
    # the full body, not just the `|` marker line), so a `Use when…` clause anywhere
    # in a multi-line description satisfies the check.
    if [ -n "$desc" ] && ! echo "$desc" | grep -qiE "Use when|Use this skill when|Use PROACTIVELY when|Use after|Trigger when|Auto-loads when|ALWAYS trigger|ALWAYS run|Trigger on|Invoke when"; then
      warn "skill '$name' missing trigger pattern (e.g. 'Use when…') in description"
    fi
  fi
done

# 6. Frontmatter completeness — commands
for f in "$CLAUDE_DIR/commands"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  if ! grep -q '^---' "$f"; then
    crit "command '$name' missing frontmatter"
  fi
  if [ -z "$(fm_get "$f" "description" --block)" ]; then
    crit "command '$name' missing description: in frontmatter"
  fi
done

# 7. Name/filename consistency — agents
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  file=$(basename "$f" .md)
  name=$(fm_get "$f" "name" --block)
  if [ -n "$name" ] && [ "$file" != "$name" ]; then
    crit "agent file='$file' name='$name' mismatch"
  fi
done

# 8. Name/filename consistency — skills
for f in "$CLAUDE_DIR/skills"/*/SKILL.md; do
  [ -f "$f" ] || continue
  dir=$(basename "$(dirname "$f")")
  # _-prefixed scaffolds ship placeholder names (e.g. your-skill-name); not deployed
  case "$dir" in _*) continue ;; esac
  name=$(fm_get "$f" "name" --block)
  if [ -n "$name" ] && [ "$dir" != "$name" ]; then
    crit "skill dir='$dir' name='$name' mismatch"
  fi
done

# 9. Tool-grant scoping (agents must have explicit tools:)
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  if ! grep -q '^tools:' "$f"; then
    crit "agent '$name' missing tools: grant (inherits all)"
  fi
done

# 10. Duplicate tools in agent grants
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  tools=$(fm_get "$f" "tools" --block)
  if [ -n "$tools" ]; then
    dups=$(echo "$tools" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort | uniq -d)
    if [ -n "$dups" ]; then
      warn "agent '$name' duplicate tools: $dups"
    fi
  fi
done

# 11. Orphaned hooks (in filesystem but not in settings.json)
if [ -f "$SETTINGS" ]; then
  for f in "$CLAUDE_DIR/hooks"/*; do
    [ -f "$f" ] || continue
    hook_name=$(basename "$f")
    [ "$hook_name" = "__pycache__" ] && continue
    # Skip hook libraries (sourced by hooks, not registered as hooks themselves).
    # The _lib.sh prefix matches the existing project scaffold convention used
    # in skills/ and agents/; install.sh's hooks glob *.{sh,py} symlinks it so
    # hook scripts can `source "$(dirname "$0")/_lib.sh"` at runtime.
    # *.md = co-located docs (JOURNAL-SCHEMA.md) — not hooks, never in settings.
    # *.json = plugin hook registry (hooks/hooks.json), not a hook script.
    # *.bak = editor/backup residue (e.g. hooks.json.test.bak from a hook-test
    # session), not a real hook — matches the F1 skip pattern in #3.
    case "$hook_name" in _*.sh|_*.py|*.bak|*.md|*.json) continue;; esac
    # Wired = settings.json (symlink mode) OR hooks/hooks.json (plugin mode).
    if ! grep -q "$hook_name" "$SETTINGS" \
       && ! grep -q "$hook_name" "$CLAUDE_DIR/hooks/hooks.json" 2>/dev/null; then
      crit "hook '$hook_name' exists in hooks/ but not wired in settings.json or hooks.json"
    fi
  done
fi

# 12. Routing table coverage (orchestrate references all agents)
# The agent fleet list lives in reference.md; SKILL.md carries only inline
# examples (SKILL.md:49 points to reference.md). Check both — an agent
# documented in either file counts as covered.
ORCH_SKILL="$CLAUDE_DIR/skills/orchestrate/SKILL.md"
ORCH_REF="$CLAUDE_DIR/skills/orchestrate/reference.md"
if [ -f "$ORCH_SKILL" ]; then
  for f in "$CLAUDE_DIR/agents"/*.md; do
    [ -f "$f" ] || continue
    agent=$(basename "$f" .md)
    if ! grep -hq "\`$agent\`" "$ORCH_SKILL" "$ORCH_REF" 2>/dev/null; then
      warn "agent '$agent' not referenced in orchestrate routing table"
    fi
  done
fi

# 13. Memory index drift
# Process substitution (not a pipe) keeps the loop in the current shell so
# crit() increments propagate — a `grep | while` runs in a subshell and the
# count would be lost (the CRIT line prints but the exit code under-reports).
MEMORY_INDEX="$MEMORY_DIR/MEMORY.md"
if [ -f "$MEMORY_INDEX" ]; then
  while IFS= read -r memf; do
    mem_path="$MEMORY_DIR/$memf"
    if [ ! -f "$mem_path" ]; then
      crit "memory references '$memf' but file missing"
    fi
  done < <(grep -oE '\([^)]+\.md\)' "$MEMORY_INDEX" | tr -d '()' | sort -u)
fi

# 14. PyCache tracked by git
if git -C "$REPO_ROOT" ls-files | grep -q '__pycache__\|\.pyc$'; then
  crit "__pycache__ or *.pyc tracked by git (should be .gitignore'd)"
fi

# 15. settings.json has commands/agents/skills arrays (not just hooks)
if [ -f "$SETTINGS" ]; then
  if ! python3 -c "import json; d=json.load(open('$SETTINGS')); exit(0 if 'commands' in d else 1)" 2>/dev/null; then
    info "settings.json missing 'commands' array — commands loaded via plugin or ~/.claude/commands/ directly"
  fi
  if ! python3 -c "import json; d=json.load(open('$SETTINGS')); exit(0 if 'agents' in d else 1)" 2>/dev/null; then
    info "settings.json missing 'agents' array — agents loaded via plugin or ~/.claude/agents/ directly"
  fi
  if ! python3 -c "import json; d=json.load(open('$SETTINGS')); exit(0 if 'skills' in d else 1)" 2>/dev/null; then
    info "settings.json missing 'skills' array — skills loaded via plugin or ~/.claude/skills/ directly"
  fi
fi

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
      warn "BOUNDARY.md stale vs repo fleet — regenerate: bash <kbg-harness>/skills/inventory/scripts/inventory-boundary.sh --repo-only > <dotfiles>/claude/BOUNDARY.md  (substitute your kbg-harness and dotfiles repo roots)"
    fi
  else
    warn "could not regenerate boundary map to check drift (inventory-boundary.sh failed)"
  fi
  rm -f "$_tmp_boundary"
fi

# 17. Bundled Python scripts compile (compile() is in-memory — writes no .pyc)
while IFS= read -r f; do
  if ! python3 -c "import sys; compile(open(sys.argv[1]).read(), sys.argv[1], 'exec')" "$f" 2>/dev/null; then
    crit "bundled script '${f#$CLAUDE_DIR/}' has a Python syntax error"
  fi
done < <(find "$CLAUDE_DIR/skills" -name '*.py' -not -path '*__pycache__*' 2>/dev/null)

# 18. Bundled shell scripts pass syntax check
while IFS= read -r f; do
  if ! bash -n "$f" 2>/dev/null; then
    crit "bundled script '${f#$CLAUDE_DIR/}' has a shell syntax error"
  fi
done < <(find "$CLAUDE_DIR/skills" -name '*.sh' 2>/dev/null)

# 19. Bundled JSON files parse
while IFS= read -r f; do
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    crit "bundled JSON '${f#$CLAUDE_DIR/}' is invalid"
  fi
done < <(find "$CLAUDE_DIR/skills" -name '*.json' 2>/dev/null)

# 20. Description length — skills, agents, commands.
# code.claude.com/docs/en/skills + /sub-agents: description max 1536 chars
# (combined with when_to_use). Over-limit is silently truncated by the runtime,
# which can cut off the negation clause and degrade routing. fm_get --block
# returns the full block-scalar body (with indent stripped), so multi-line
# descriptions are measured accurately against the limit.
DESC_MAX=1536
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/agents"/*.md "$CLAUDE_DIR/commands"/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  label=$(basename "$f" .md); [ "$label" = "SKILL" ] && label=$(basename "$(dirname "$f")")
  desc=$(fm_get "$f" "description" --block)
  len=${#desc}
  if [ "$len" -gt "$DESC_MAX" ]; then
    warn "'$label' description is $len chars (>$DESC_MAX; runtime truncates — trim it)"
  fi
done

# 21. Agent model value — must be a documented alias or a full claude-* model ID.
# code.claude.com/docs/en/model-config: aliases sonnet|opus|haiku|inherit, or a
# full ID (claude-opus-4-8, claude-sonnet-4-6, ...). model is optional (defaults
# to inherit), so a missing field is fine — only a present-but-bogus value warns.
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  model=$(fm_get "$f" "model" --block)
  [ -n "$model" ] || continue
  case "$model" in
    sonnet|opus|haiku|inherit) ;;
    claude-*) ;;
    *) warn "agent '$name' model='$model' is not an alias (sonnet|opus|haiku|inherit) or a claude-* ID" ;;
  esac
done

# 22. Hook config validity — settings.json (checks C–F).
# Verified against code.claude.com/docs/en/hooks (31-event canonical set, fetched
# 2026-05-30). Findings are WARN not CRIT: vendor docs lag features (Rule 1), so
# an unrecognized event/type may be real-but-undocumented — flag for a human, do
# not fail the build. A bad regex, by contrast, genuinely never matches.
if [ -f "$SETTINGS" ]; then
  while IFS= read -r finding; do
    [ -n "$finding" ] && warn "$finding"
  done < <(python3 - "$SETTINGS" <<'PYEOF'
import json, re, sys
# Canonical event set — code.claude.com/docs/en/hooks "Hook lifecycle" table.
DOC_EVENTS = {
    "SessionStart","Setup","UserPromptSubmit","UserPromptExpansion","PreToolUse",
    "PermissionRequest","PermissionDenied","PostToolUse","PostToolUseFailure",
    "PostToolBatch","Notification","MessageDisplay","SubagentStart","SubagentStop",
    "TaskCreated","TaskCompleted","Stop","StopFailure","TeammateIdle",
    "InstructionsLoaded","ConfigChange","CwdChanged","FileChanged","WorktreeCreate",
    "WorktreeRemove","PreCompact","PostCompact","Elicitation","ElicitationResult",
    "SessionEnd",
}
VALID_TYPES = {"command","http","mcp","agent","prompt"}
AC_MAX = 10000
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)  # JSON validity is covered elsewhere; don't double-report.
hooks = cfg.get("hooks", {})
if not isinstance(hooks, dict):
    sys.exit(0)
for ev, arr in hooks.items():
    # E: event name in documented set
    if ev not in DOC_EVENTS:
        print(f"hook event '{ev}' not in documented event set (typo? or undocumented — verify)")
    if not isinstance(arr, list):
        continue
    for blk in arr:
        if not isinstance(blk, dict):
            continue
        # D: matcher must be a compilable regex. '*' and '' are wildcard
        # sentinels (match-all), valid to Claude Code but not to Python re —
        # skip them so they don't false-positive.
        m = blk.get("matcher")
        if isinstance(m, str) and m not in ("", "*"):
            try:
                re.compile(m)
            except re.error as e:
                print(f"hook '{ev}' matcher {m!r} is not a valid regex ({e})")
        for h in blk.get("hooks", []):
            if not isinstance(h, dict):
                continue
            # C: handler type
            t = h.get("type")
            if t is not None and t not in VALID_TYPES:
                print(f"hook '{ev}' handler type '{t}' not in {sorted(VALID_TYPES)}")
            # F: static additionalContext length. Runtime-generated context
            # (command-type stdout) is invisible here; this only catches a
            # literal field hardcoded in settings.json.
            ac = h.get("additionalContext")
            if isinstance(ac, str) and len(ac) > AC_MAX:
                print(f"hook '{ev}' static additionalContext is {len(ac)} chars (>{AC_MAX}; truncated)")
PYEOF
)
fi

# 23. Name format — skills + agents. code.claude.com/docs/en/skills + /sub-agents:
# name = lowercase letters, digits, hyphens only; max 64 chars. A bad name breaks
# discovery/namespacing. Scaffolds (_*) ship placeholder names — skipped.
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  label=$(basename "$f" .md); [ "$label" = "SKILL" ] && label=$(basename "$(dirname "$f")")
  nm=$(fm_get "$f" "name" --block)
  [ -n "$nm" ] || continue
  if ! printf '%s' "$nm" | grep -qE '^[a-z0-9-]{1,64}$'; then
    crit "'$label' name='$nm' violates format (lowercase/digits/hyphens, <=64 chars)"
  fi
done

# 24. Agent tool-grant tokens — each token in tools: must be a real Claude Code
# tool. code.claude.com/docs/en/tools-reference. Strips a (specifier) suffix
# before checking, so 'Bash(git:*)' validates as 'Bash'. Catches typos that
# silently drop a grant (e.g. 'Bsh' grants nothing). Process substitution (not a
# pipe) keeps warn() in the current shell so WARN_COUNT folds into the exit code.
VALID_TOOLS="Read Write Edit MultiEdit Glob Grep Bash WebFetch WebSearch NotebookEdit Task Agent TodoWrite BashOutput KillShell SlashCommand"
while IFS= read -r badtok; do
  warn "$badtok"
done < <(
  for f in "$CLAUDE_DIR/agents"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    tv=$(fm_get "$f" "tools" --block)
    [ -n "$tv" ] || continue
    for tok in $(echo "$tv" | tr ',' ' '); do
      base="${tok%%(*}"
      case " $VALID_TOOLS " in
        *" $base "*) ;;
        *) echo "agent '$name' tools: token '$tok' is not a known Claude Code tool" ;;
      esac
    done
  done
)

# 25. Agent skills: references resolve to a real skill — repo or installed global
# (~/.claude/skills/). code.claude.com/docs/en/sub-agents: the skills: array
# names skills made available to the agent. A dangling ref (after a rename or
# delete) silently provides nothing. A plugin-scoped ref (plugin:name) resolves
# on its base name.
_known_skills=$(mktemp)
{
  for d in "$CLAUDE_DIR/skills"/[!_]*/; do [ -d "$d" ] && basename "$d"; done                       # [!_]*/ skips _-prefixed scaffolds (e.g. _template)
  [ -d "$HOME/.claude/skills" ] && for d in "$HOME/.claude/skills"/[!_]*/; do [ -d "$d" ] && basename "$d"; done
} | sort -u > "$_known_skills"
while IFS= read -r ref_line; do
  warn "$ref_line"
done < <(
  for f in "$CLAUDE_DIR/agents"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    # extract the YAML list under `skills:` up to the next top-level key
    awk '
      /^skills:[[:space:]]*$/ { in_s=1; next }
      in_s && /^[[:space:]]+-[[:space:]]+/ { sub(/^[[:space:]]+-[[:space:]]+/,""); sub(/[[:space:]]+$/,""); print; next }
      in_s && /^[^[:space:]]/ { in_s=0 }
    ' "$f" | while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      base="${ref##*:}"   # strip plugin: prefix
      if ! grep -qx "$ref" "$_known_skills" && ! grep -qx "$base" "$_known_skills"; then
        echo "agent '$name' skills: ref '$ref' resolves to no known skill"
      fi
    done
  done
)
rm -f "$_known_skills"

# 26. CLAUDE.md @-import resolution — every `@file` reference at line start must
# resolve to a real file relative to the importing CLAUDE.md. Claude Code inlines
# these on load; a dangling ref (after an imported doctrine file is renamed or
# moved) silently loads nothing, dropping that doctrine from every session with
# no error. Today only claude/CLAUDE.md imports (@METHODOLOGY.md, @RTK.md), but
# the check covers any CLAUDE.md in the repo. CRIT: the break is unambiguous and
# silently strips core behavior. Process substitution (not a pipe) keeps crit()
# in the current shell so the count folds into the exit code.
while IFS= read -r cmd; do
  [ -f "$cmd" ] || continue
  cmd_dir=$(dirname "$cmd")
  while IFS= read -r line; do
    ref="${line#@}"
    ref="${ref%%[[:space:]]*}"
    [ -n "$ref" ] || continue
    case "$ref" in
      '~/'*) target="$HOME/${ref#'~/'}" ;;
      /*)    target="$ref" ;;
      *)     target="$cmd_dir/$ref" ;;
    esac
    if [ ! -e "$target" ]; then
      crit "CLAUDE.md '${cmd#$REPO_ROOT/}' import '@$ref' resolves to no file"
    fi
  done < <(grep -E '^@[^[:space:]]' "$cmd")
done < <(find "$REPO_ROOT" -name 'CLAUDE.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

# 27. Test-honesty / tautology detector — METHODOLOGY Rule 9 static check.
# Catches "test that can't fail when behavior changes" by greppable patterns
# in test files only. Paired with claude/rules/test-honesty.md (write-time hint)
# and /feature-dev Phase 5 TDD default (workflow gate).
while IFS= read -r f; do
  [ -e "$f" ] || continue
  rel="${f#$REPO_ROOT/}"
  # 27.1 — tautological assertion: assert True / assert False / assertEqual(x, x)
  if grep -nE 'assert[[:space:]]+(True|true|False|false)[[:space:]]*[),]' "$f" >/dev/null 2>&1; then
    crit "test-honesty: '$rel' has tautological assert True/False"
  fi
  # 27.2 — identity / repr assertion: type(x) is type(x), repr(x) == repr(x),
  # isinstance(x, type(x)). Passes regardless of behavior.
  if grep -nE '(type\(.*\)[[:space:]]+(is|==)[[:space:]]+type\(|repr\(.*\)[[:space:]]*==[[:space:]]*repr|isinstance\(.*,[[:space:]]*type\()' "$f" >/dev/null 2>&1; then
    warn "test-honesty: '$rel' asserts on identity/repr, not behavior (Rule 9)"
  fi
  # 27.3 — placeholder test name: smoke / basic / works / sanity / simple / temp
  if grep -nE 'def[[:space:]]+test_(smoke|basic|works?|sanity|simple|temp|placeholder)\b' "$f" >/dev/null 2>&1; then
    warn "test-honesty: '$rel' has test_<placeholder> name (encode WHY, not WHAT)"
  fi
  # 27.4 — test function body is `pass` or `...` after def+optional docstring.
  # Grep for `def test_` line, then look 1-3 lines after for pass-only/...-only.
  if awk '
    /^def[[:space:]]+test_/ { hit=1; body=0; next }
    hit && /^[[:space:]]*$/ { next }
    hit && /^[[:space:]]*"""/ { in_doc=!in_doc; next }
    hit && /^[[:space:]]*("""|'"'"''"'"''')/ { in_doc=!in_doc; next }
    hit && !in_doc { body=1; if ($0 ~ /^[[:space:]]+(pass|\.\.\.)[[:space:]]*$/) { print FILENAME":"NR":"$0; exit 0 }; hit=0 }
    { hit=0 }
  ' "$f" | grep -q .; then
    warn "test-honesty: '$rel' has test_ function with pass/... body (no assertion)"
  fi
done < <(find "$REPO_ROOT" -type f \( \
    -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.test.jsx' -o \
    -name '*.spec.ts' -o -name '*.spec.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' -o \
    -name 'test_*.py' -o -name '*_test.py' \
  \) -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

# 28. Frontmatter YAML validity — strict-parse every agent/skill/command
# frontmatter. The grep-based fm_get reads `name:` even out of a malformed
# block, so a broken double-quoted description (a stray `"` mid-string) or an
# unquoted `Key: value` colon passes every other check here yet makes Claude
# Code silently DROP the agent/skill from the runtime registry ("agent type
# 'X' not found"). A load-breaking defect = CRITICAL (pre-commit blocks it).
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  # One python pass over all frontmatters; emits "<path>\t<error>" per broken
  # file. Process substitution (not a pipe) keeps crit() in the current shell
  # so the count propagates — same reason as #13.
  while IFS=$'\t' read -r badf err; do
    [ -n "$badf" ] || continue
    crit "frontmatter: '${badf#"$REPO_ROOT"/}' has invalid YAML — Claude Code won't load it: $err"
  done < <(python3 - "$CLAUDE_DIR" <<'PY'
import sys, os, glob
try:
    import yaml
except Exception:
    sys.exit(0)
root = sys.argv[1]
def frontmatter(path):
    t = open(path, encoding='utf-8').read()
    if not t.startswith('---'):
        return None
    end = t.find('\n---', 3)
    return t[3:end] if end != -1 else None
files = (sorted(glob.glob(os.path.join(root, 'agents', '*.md')))
         + sorted(glob.glob(os.path.join(root, 'commands', '*.md')))
         + sorted(glob.glob(os.path.join(root, 'skills', '*', 'SKILL.md'))))
for f in files:
    # skip _-prefixed scaffolds (e.g. skills/_template) — not real fleet
    if os.path.basename(f).startswith('_') or os.path.basename(os.path.dirname(f)).startswith('_'):
        continue
    fm = frontmatter(f)
    if fm is None:
        continue
    try:
        yaml.safe_load(fm)
    except yaml.YAMLError as e:
        print(f"{f}\t{str(e).splitlines()[0].strip()}")
PY
)
else
  # Fail loud about the skip (Rule 12) — a silently-skipped validator is the
  # exact failure mode this check exists to catch.
  warn "frontmatter YAML validity check skipped — python3+PyYAML unavailable"
fi

# 29. Gate↔evidence separation (C1 evidence-journal invariant) — a hook that
# emits a permissionDecision (hook_decision) must NOT also call journal_append
# in the same file. Gate hooks decide; audit hooks journal. hook_decision exits
# 0, so any journal_append alongside it is either dead code or a decision path
# that journals before it decides — both wrong. See claude/hooks/JOURNAL-SCHEMA.md.
# Skip _*.sh libraries: _lib.sh DEFINES both functions and is not itself a hook.
for f in "$CLAUDE_DIR/hooks"/*.sh; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  case "$name" in _*.sh) continue;; esac
  if grep -qw 'journal_append' "$f" && grep -qw 'hook_decision' "$f"; then
    crit "hook '$name' calls BOTH journal_append and hook_decision — gate hooks decide, audit hooks journal; separate them (JOURNAL-SCHEMA.md)"
  fi
done

# 30. Eval-target freshness — every `**/evals.json` and the baseline-eval
# driver carries a `last_reviewed:` (ISO date) field. If the date is older
# than KBG_EVAL_MAX_AGE_DAYS (default 180) AND there's no sibling
# `last_reviewed_reason:` justifying the staleness, emit info. This catches
# the "evals were great 6 months ago, has the skill drifted?" case the
# per-fix gate-rot check can't see — gate-rot is per-fix, this is per-target.
# Default of 180d matches decay-cadence quarter; tune via env var.
# 2026-06-11: added in response to the Harness-Loop-Engineer audit FIX-2.
KBG_EVAL_MAX_AGE_DAYS="${KBG_EVAL_MAX_AGE_DAYS:-180}"
if command -v python3 >/dev/null 2>&1; then
  # Collect candidate files. We pass paths via NUL delimiters so a path with
  # spaces (rare in this repo, but cheap to handle) doesn't get mangled.
  EVAL_TARGETS=()
  while IFS= read -r -d '' f; do EVAL_TARGETS+=("$f"); done < <(find "$CLAUDE_DIR/skills" -type f -name 'evals.json' -print0 2>/dev/null)
  while IFS= read -r -d '' f; do EVAL_TARGETS+=("$f"); done < <(find "$REPO_ROOT/scripts" -maxdepth 2 -type f -name 'run-baseline-eval.py' -print0 2>/dev/null)
  if [ "${#EVAL_TARGETS[@]}" -gt 0 ]; then
    while IFS=$'\t' read -r eval_path age_days has_reason reason_text; do
      [ -n "$eval_path" ] || continue
      rel="${eval_path#"$REPO_ROOT"/}"
      if [ "$age_days" = "missing" ]; then
        # No last_reviewed field at all. The whole point of this check is
        # to surface files that haven't been touched — but a documented
        # `last_reviewed_reason:` (per the convention introduced in
        # 2026-06-11 to defer until a human gets to a real review) IS
        # a touch: the file was opened, the deferral was a deliberate
        # decision, and the quarterly cadence owns the rotation. Honor it
        # the same way the stale branch does.
        if [ "$has_reason" != "1" ]; then
          info "eval-target freshness: $rel missing 'last_reviewed:' field — add one (YYYY-MM-DD)"
        fi
      elif [ "$age_days" -gt "$KBG_EVAL_MAX_AGE_DAYS" ] 2>/dev/null && [ "$has_reason" != "1" ]; then
        info "eval-target freshness: $rel last reviewed $age_days days ago — revisit (or add last_reviewed_reason: to defer)"
      fi
    done < <(KBG_EVAL_MAX_AGE_DAYS="$KBG_EVAL_MAX_AGE_DAYS" python3 - "${EVAL_TARGETS[@]}" <<'PY' 2>/dev/null
import datetime as dt, json, os, re, sys
targets = sys.argv[1:]
max_age = int(os.environ.get("KBG_EVAL_MAX_AGE_DAYS", "180"))
today = dt.date.today()
# .py header: scan first 50 lines for a `last_reviewed: YYYY-MM-DD` line.
# evals.json: scan the first ~3KB for the same field (kept loose since
# people put it in different positions — sibling `last_reviewed_reason:`
# counts as a documented justification for staleness).
LINE_RE = re.compile(r"^[\s#/*-]*last_reviewed:\s*(\d{4}-\d{2}-\d{2})", re.MULTILINE)
# Allow JSON key form ("last_reviewed_reason": …) in addition to YAML and
# comment form. The leading char class is greedy by design — the literal
# 'last_reviewed_reason' token after it pins the match to the right key
# (so 'blast_reviewed_reason' / 'skill_name' do not match).
REASON_RE = re.compile(r"""^[\s#/*'"]*last_reviewed_reason["']?\s*:\s*\S+""", re.MULTILINE)
for path in targets:
    try:
        text = open(path, encoding="utf-8", errors="replace").read(8192)
    except OSError:
        continue
    m = LINE_RE.search(text)
    if not m:
        # Try JSON parse to catch "last_reviewed" as a key (camelCase OK).
        try:
            data = json.loads(open(path, encoding="utf-8", errors="replace").read())
            if isinstance(data, dict):
                v = data.get("last_reviewed") or data.get("lastReviewed")
                if v:
                    try: dt.date.fromisoformat(str(v))
                    except ValueError: pass
                    else:
                        # JSON path: look for reason at the same level
                        reason = data.get("last_reviewed_reason") or data.get("lastReviewedReason")
                        if reason:
                            print(f"{path}\t{(today - dt.date.fromisoformat(str(v))).days}\t1\t{reason}")
                            continue
                        print(f"{path}\t{(today - dt.date.fromisoformat(str(v))).days}\t0\t")
                        continue
                # No `last_reviewed` AND no `last_reviewed:` line — but the
                # file may still carry a `last_reviewed_reason:` in the JSON
                # (the convention introduced to defer stamping until a
                # human gets to a real review). The same justification that
                # suppresses the stale branch should suppress the missing
                # branch, so we don't surface noise for deliberately-deferred
                # targets.
                reason_only = data.get("last_reviewed_reason") or data.get("lastReviewedReason")
                if reason_only:
                    print(f"{path}\tmissing\t1\t{reason_only}")
                    continue
        except (OSError, ValueError):
            pass
        print(f"{path}\tmissing\t0\t")
        continue
    try:
        d = dt.date.fromisoformat(m.group(1))
    except ValueError:
        # Line matched `last_reviewed:` but the date was unparseable.
        # Treat as missing — and check for a `last_reviewed_reason:`
        # justification before flagging (same convention as the JSON branch).
        if REASON_RE.search(text):
            reason_text = REASON_RE.search(text).group(0)
            print(f"{path}\tmissing\t1\t{reason_text}")
        else:
            print(f"{path}\tmissing\t0\t")
        continue
    has_reason = "1" if REASON_RE.search(text) else "0"
    age = (today - d).days
    reason_text = REASON_RE.search(text).group(0) if has_reason == "1" else ""
    print(f"{path}\t{age}\t{has_reason}\t{reason_text}")
PY
)
  fi
else
  warn "eval-target freshness check skipped — python3 unavailable"
fi

# 32. Autonomy invariant guardrail — round-2 drill-down (2026-06-12)
# found that the load-bearing autonomy invariant (CONTEXT.md §Invariants:
# "no autonomous or unattended self-repair loop, and no multi-iteration
# loop that runs without a human gate between iterations") had no
# deterministic check. The invariant is enforced socially (in code
# review + CHANGELOG notes) via the `disable-model-invocation: true`
# frontmatter on skills/recursive-improve/SKILL.md. This check makes
# the guardrail deterministic. If this check ever fires on a real
# repo, the invariant has regressed and the harness is one
# model-version away from self-rewriting — emit CRIT, not WARN.
#
# Implementation note: we read only the first 20 lines (frontmatter
# region) of recursive-improve/SKILL.md. The check is exact-match on
# "disable-model-invocation: true" — a regression guard against typos
# (e.g. "True", "yes", "1") that would silently disable the gate.
# The check is hermetic (single file read, no JSON parse, no
# transitive dependencies). If the skill is renamed or removed, the
# check silently passes (no file = no invariant to guard); this is
# intentional — the invariant is about THIS skill being self-binding,
# not about a future skill needing the same property.
if [ -f "$CLAUDE_DIR/skills/recursive-improve/SKILL.md" ]; then
  if ! head -20 "$CLAUDE_DIR/skills/recursive-improve/SKILL.md" | grep -qF "disable-model-invocation: true"; then
    crit "skills/recursive-improve/SKILL.md: missing 'disable-model-invocation: true' in frontmatter (autonomy invariant regressed — see CONTEXT.md §Invariants + ADR 0002)"
  fi
fi

# 31. Schema-rot detector — round-2 (2026-06-11) found that the pre-emit
# validator at scripts/review-pr-journal-pre-emit-validator.py is scoped
# to the review-pr journaler's enum regexes only. No general detector
# existed for: skill I/O contract drift, plugin.json version drift,
# settings.json permission drift, or hooks.json schema drift. The
# decay-cadence is the unifying ritual but lives in
# docs/harness-decay-cadence.md as a doc, not as a check. This check
# runs 4 sub-checks; only the hooks.json sub-check is STRUCTURAL (crit);
# the rest are ADVISORY (info). The check surfaces drift; the human acts.
#
# Sub-check 31.1 — Skill SKILL.md section presence: emit a SINGLE info per
# skill listing every missing canonical section. This keeps noise at
# 1-per-skill (not N-per-skill) and still catches drift: a skill that
# USED to have the sections but no longer does will show up in audit
# output as a stable, actionable bullet. Sections are: ## Input
# Contract, ## Output Format, ## Failure Modes. The check is hermetic —
# it only inspects the file itself, not the references the contract
# might name (URLs / external sources can't be checked from here).
# Sub-check 31.2 — plugin.json / marketplace.json: emit info if the
# `version` field is older than KBG_PLUGIN_VERSION_MAX_AGE_DAYS
# (default 30) AND has no sibling `last_reviewed:` / `last_reviewed_reason:`
# justification. Emit crit if the file does not parse as JSON or
# `version` is missing. Defense in depth: claude plugin validate
# already enforces the JSON shape, but a missing `version` is the
# specific failure mode that breaks the cache-resolver at audit.sh:73.
# Sub-check 31.3 — settings.json permission re-audit bookmark: per
# decay-cadence §Permission re-audit, the kbg-harness equivalent is
# a `## Permission re-audit` section with a `last_permission_review:
# YYYY-MM-DD` marker in `docs/harness-decay-cadence.md`. Emit info if
# the marker is older than KBG_PERM_REAUDIT_MAX_AGE_DAYS (default 90,
# quarterly cadence). (The plugin.json `last_permission_review_sha`
# equivalent was named in the original doc-comment but never
# implemented — doc trimmed in round-2 audit reconcile 2026-06-12
# to match the actual check below; lines ~1008-1039.)
# Sub-check 31.4 — hooks.json schema: STRUCTURAL. Every `matcher` in the
# JSON must be a non-empty string, every `hooks[]` entry must have a
# `type` field, every `command` value must be non-empty. Emit crit on
# violation. A malformed hooks.json will cause Claude Code to fail to
# load hooks at runtime — a silent config-drift failure mode the rest
# of the audit cannot see.
if command -v python3 >/dev/null 2>&1; then
  # Run all 4 sub-checks in a single python invocation and dispatch each
  # TSV line to info / warn / crit. We use a here-doc via process
  # substitution so the bash helpers can keep their counters (subshells
  # would lose the increments).
  while IFS=$'\t' read -r kind payload extra; do
    [ -n "$kind" ] || continue
    case "$kind" in
      SKILL_MISSING)         info "schema-rot: skill '$payload' is missing canonical sections ($extra) — possible I/O contract drift" ;;
      PLUGIN_PARSE_FAIL)     crit "schema-rot: $(basename "$payload" 2>/dev/null || echo "$payload") failed to parse as JSON" ;;
      PLUGIN_NO_VERSION)     crit "schema-rot: $(basename "$payload" 2>/dev/null || echo "$payload") has no 'version' field (cache-resolver will break)" ;;
      PLUGIN_STALE)          info "schema-rot: $payload — consider a version bump (30d cadence per decay-cadence)" ;;
      PERM_BOOKMARK_MISSING) info "schema-rot: $payload — add a 'last_permission_review:' marker (quarterly cadence per decay-cadence)" ;;
      PERM_BOOKMARK_BAD)     warn "schema-rot: permission re-audit marker date is unparseable: $payload" ;;
      PERM_BOOKMARK_STALE)   info "schema-rot: permission re-audit $payload" ;;
      HOOKS_PARSE_FAIL)      crit "schema-rot: hooks.json failed to parse: $payload" ;;
      HOOKS_SHAPE_FAIL)      crit "schema-rot: hooks.json — $payload" ;;
    esac
  done < <(python3 - "$CLAUDE_DIR" "$REPO_ROOT" <<'PY' 2>/dev/null
import datetime as dt, json, os, re, sys
claude_dir, repo_root = sys.argv[1], sys.argv[2]
today = dt.date.today()

# 31.1: Skill SKILL.md section presence (info, single bullet per skill)
# Deferral: a sibling `last_reviewed_reason:` marker (in SKILL.md frontmatter
# OR in the skill's evals/evals.json) suppresses the INFO — same convention
# section #30 uses for eval-target freshness and the plugin-version check at
# 31.2 uses for plugin.json. Decay-cadence (docs/harness-decay-cadence.md)
# owns the quarterly human sweep that revisits these; the audit is sensor
# only, sensor-with-documented-deferral is preferred over stubbing.
skills_dir = os.path.join(claude_dir, "skills")
REQUIRED = ["## Input Contract", "## Output Format", "## Failure Modes"]
# Same form as #30: JSON "last_reviewed_reason":, YAML `last_reviewed_reason:`,
# or comment `# last_reviewed_reason:`. See audit.sh LINE_RE/REASON_RE pair.
REASON_RE = re.compile(r"""^[\s#/*'"]*last_reviewed_reason["']?\s*:\s*\S+""", re.MULTILINE)
if os.path.isdir(skills_dir):
    for name in sorted(os.listdir(skills_dir)):
        # skip _-prefixed scaffolds (not real fleet, may have placeholders)
        if name.startswith("_"):
            continue
        path = os.path.join(skills_dir, name, "SKILL.md")
        if not os.path.isfile(path):
            continue
        try:
            text = open(path, encoding="utf-8", errors="replace").read(65536)
        except OSError:
            continue
        missing = [s for s in REQUIRED if s not in text]
        if not missing:
            continue
        # Deferral check: frontmatter on SKILL.md OR sibling evals.json.
        # Mirrors the #30 eval-target pattern — see audit.sh:807.
        if REASON_RE.search(text):
            deferred = True
        else:
            evals_path = os.path.join(skills_dir, name, "evals", "evals.json")
            deferred = False
            if os.path.isfile(evals_path):
                try:
                    evals_text = open(evals_path, encoding="utf-8", errors="replace").read(65536)
                except OSError:
                    evals_text = ""
                deferred = bool(REASON_RE.search(evals_text))
        if not deferred:
            print(f"SKILL_MISSING\t{name}\t{', '.join(missing)}")

# 31.2: plugin.json / marketplace.json version validity + cadence
# For plugin.json the top-level `version` is canonical. For
# marketplace.json the version lives in `plugins[].version` (the
# marketplace is a list of plugins, not a single plugin manifest).
PLUGIN_DIR = os.path.join(repo_root, ".claude-plugin")
def _check_plugin_version(p, version_value, reason):
    if not isinstance(version_value, str) or not version_value.strip():
        print(f"PLUGIN_NO_VERSION\t{os.path.basename(p)}")
        return
    try:
        mtime = dt.date.fromtimestamp(os.path.getmtime(p))
    except OSError:
        return
    age = (today - mtime).days
    if age > 30 and not reason:
        print(f"PLUGIN_STALE\t{os.path.basename(p)}\tversion={version_value}\tage_days={age}")
p_plugin = os.path.join(PLUGIN_DIR, "plugin.json")
if os.path.isfile(p_plugin):
    try:
        data = json.loads(open(p_plugin, encoding="utf-8", errors="replace").read())
    except (OSError, ValueError):
        print(f"PLUGIN_PARSE_FAIL\tplugin.json")
    else:
        if not isinstance(data, dict):
            print(f"PLUGIN_PARSE_FAIL\tplugin.json\t(not an object)")
        else:
            _check_plugin_version(
                p_plugin,
                data.get("version"),
                data.get("last_reviewed_reason") or "",
            )
p_market = os.path.join(PLUGIN_DIR, "marketplace.json")
if os.path.isfile(p_market):
    try:
        data = json.loads(open(p_market, encoding="utf-8", errors="replace").read())
    except (OSError, ValueError):
        print(f"PLUGIN_PARSE_FAIL\tmarketplace.json")
    else:
        if not isinstance(data, dict):
            print(f"PLUGIN_PARSE_FAIL\tmarketplace.json\t(not an object)")
        else:
            # marketplace.json: per the claude-code-marketplace.json
            # schema, `plugins[].version` is OPTIONAL — the actual
            # version lives in plugin.json. We only STALE-check the
            # marketplace file itself (its mtime is the real signal
            # that the marketplace hasn't been touched in 30d); we
            # do NOT crit-fire on missing version (that would be a
            # false positive on every marketplace that doesn't
            # duplicate the version field).
            try:
                mtime = dt.date.fromtimestamp(os.path.getmtime(p_market))
            except OSError:
                pass
            else:
                age = (today - mtime).days
                if age > 30:
                    print(f"PLUGIN_STALE\tmarketplace.json\ttop-level\tage_days={age}")

# 31.3: settings.json / decay-cadence permission re-audit bookmark
# decay-cadence lives at docs/harness-decay-cadence.md. Look in both
# possible locations (extracted kbg-harness vs. dotfiles checkout).
cadence_candidates = [
    os.path.join(repo_root, "docs", "harness-decay-cadence.md"),
    os.path.join(claude_dir, "docs", "harness-decay-cadence.md"),
]
cadence_path = next((p for p in cadence_candidates if os.path.isfile(p)), None)
PERM_MAX_AGE = 90
if cadence_path is None:
    print("PERM_BOOKMARK_MISSING\tdocs/harness-decay-cadence.md not found")
else:
    try:
        text = open(cadence_path, encoding="utf-8", errors="replace").read(65536)
    except OSError:
        text = ""
    # Marker shape: a `last_permission_review_sha: YYYY-MM-DD ...` line
    # (the `_sha` suffix is optional in the regex so older markers
    # without a SHA still get picked up).
    m = re.search(r"^[\s#/*-]*last_permission_review(?:_sha)?:\s*(\d{4}-\d{2}-\d{2})",
                  text, re.MULTILINE)
    if not m:
        print(f"PERM_BOOKMARK_MISSING\treview-marker not found in {os.path.relpath(cadence_path, repo_root)}")
    else:
        try:
            d = dt.date.fromisoformat(m.group(1))
        except ValueError:
            print(f"PERM_BOOKMARK_BAD\t{m.group(1)}")
        else:
            age = (today - d).days
            if age > PERM_MAX_AGE:
                print(f"PERM_BOOKMARK_STALE\treviewed {age} days ago (cadence: {PERM_MAX_AGE}d)")

# 31.4: hooks.json schema (STRUCTURAL, crit)
hooks_json_candidates = [
    os.path.join(repo_root, "hooks", "hooks.json"),
    os.path.join(claude_dir, "hooks", "hooks.json"),
]
hooks_path = next((p for p in hooks_json_candidates if os.path.isfile(p)), None)
if hooks_path is not None:
    try:
        data = json.loads(open(hooks_path, encoding="utf-8", errors="replace").read())
    except (OSError, ValueError) as e:
        print(f"HOOKS_PARSE_FAIL\t{e}")
    else:
        # Top-level shape: {"hooks": {"EventName": [{"matcher": "x", "hooks": [...]}, ...]}}
        hooks_root = data.get("hooks") if isinstance(data, dict) else None
        if not isinstance(hooks_root, dict):
            print("HOOKS_SHAPE_FAIL\tmissing top-level 'hooks' object")
        else:
            for event_name, groups in hooks_root.items():
                if not isinstance(groups, list):
                    print(f"HOOKS_SHAPE_FAIL\t{event_name}: not a list")
                    continue
                for gi, group in enumerate(groups):
                    if not isinstance(group, dict):
                        print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}]: not an object")
                        continue
                    # matcher is OPTIONAL in the spec. If present, must be a string
                    # (empty string is valid per vendor convention — empty matcher =
                    # "match all known sources", used for events with multi-source
                    # semantics like ConfigChange. See hooks/config-change-log.sh
                    # header for the rationale.) Refined after round-2 reconcile
                    # (2026-06-12): F2 check #31's "must be non-empty" was too
                    # strict and flagged the legitimate ConfigChange empty matcher.
                    matcher = group.get("matcher")
                    if matcher is not None and not isinstance(matcher, str):
                        print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].matcher: not a string")
                    inner = group.get("hooks")
                    if not isinstance(inner, list) or not inner:
                        print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks: missing or empty")
                        continue
                    for hi, h in enumerate(inner):
                        if not isinstance(h, dict):
                            print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}]: not an object")
                            continue
                        if not isinstance(h.get("type"), str) or not h["type"].strip():
                            print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].type: missing/empty")
                        if not isinstance(h.get("command"), str) or not h["command"].strip():
                            print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].command: missing/empty")
PY
)
else
  warn "schema-rot check skipped — python3 unavailable"
fi

# ── summary ──────────────────────────────────────────────────────────

echo ""
echo "=== Summary ==="
echo "Critical: $CRIT_COUNT"
echo "Warnings: $WARN_COUNT"
echo "Info:     $INFO_COUNT"
TOTAL=$((CRIT_COUNT + WARN_COUNT))
echo ""
echo "Exit: $TOTAL"
exit $TOTAL
