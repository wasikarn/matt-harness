#!/usr/bin/env bash
# audit.sh — automated health check for the custom Claude Code ecosystem.
# Usage: bash audit.sh [<repo-root>] [--plugin-cache <path>]
# Exit code = number of findings (0 = clean).
set -euo pipefail
# Hooks moved into subdirs (gates/, advisory/, lifecycle/, …); the per-hook
# checks (#3/#11/#29) and the Fleet count must recurse, not glob top-level —
# else they silently scan 0 of ~36 real hooks (green-because-empty).
shopt -s globstar

# Parse args. Positional [<repo-root>] first; optional --plugin-cache <path>
# second. Keep backward-compat: a single arg is treated as repo-root (the old
# call shape `bash audit.sh <repo>` still works).
REPO_ROOT=""
PLUGIN_CACHE_ARG=""
STALENESS_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-cache) PLUGIN_CACHE_ARG="${2:-}"; shift 2 ;;
    --plugin-cache=*) PLUGIN_CACHE_ARG="${1#--plugin-cache=}"; shift ;;
    --staleness-only) STALENESS_ONLY=1; shift ;;
    *) [ -z "$REPO_ROOT" ] && REPO_ROOT="$1"; shift ;;
  esac
done
REPO_ROOT="${REPO_ROOT:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
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

# AUDIT-1: --staleness-only flag — emit a JSON list of {name, last_fired,
# days_silent, fallback_role, ...} joined from hooks/sensors.json (Wave 1
# registry) and the governance evidence journal. Consumed by HOOK-1
# (Wave 2) at SessionStart to apply Q3 severity gating. Runs BEFORE the
# rest of the audit so the non-flag path is byte-identical: this block
# is the only difference vs upstream, and it early-exits when set.
# BASH_SOURCE-stable: REGISTRY resolves from the script's own location
# (line 53) so the path is correct whether the script runs from the
# source tree, the plugin cache, or with no <repo> arg. Degrades to `[]`
# if the registry is missing (the registry may be rolled back
# independently of this flag).
if [ "$STALENESS_ONLY" = "1" ]; then
  # The default $REPO_ROOT fallback (line 19: /../../../..) is 1 level
  # too high — it resolves to the *parent* of the kbg-harness repo when
  # no <repo> arg is given. The brief requires this flag to work with
  # OR without the optional <repo> argument, so we resolve the registry
  # via BASH_SOURCE instead of depending on $REPO_ROOT. This also keeps
  # the registry path correct in plugin-cache invocations (the script
  # is the same file regardless of where the cache copy lives).
  REGISTRY="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../hooks" && pwd)/sensors.json"
  if [ ! -f "$REGISTRY" ]; then
    echo "[]"
    exit 0
  fi
  # Honor the JOURNAL-SCHEMA.md test override (CLAUDE_JOURNAL_PATH). Same
  # convention journal_append() uses — keep the read side consistent.
  JOURNAL="${CLAUDE_JOURNAL_PATH:-$HOME/.claude/governance-events.jsonl}"
  python3 - "$REGISTRY" "$JOURNAL" <<'PY' 2>/dev/null || echo "[]"
import datetime as dt, json, os, sys
registry_path, journal_path = sys.argv[1], sys.argv[2]
now = dt.datetime.now(dt.timezone.utc)
# Build name -> last_fired_iso from the journal. Hook basenames in the
# journal match the registry's `name` field (basename without .sh/.py
# extension; see JOURNAL-SCHEMA.md envelope: `hook` is the script id,
# not a path). A sensor that never journaled is `null` by design — the
# absence is the signal the notifier is built to detect.
last_fired = {}
if os.path.isfile(journal_path):
    with open(journal_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            h = d.get("hook")
            ts = d.get("ts")
            if not h or not ts:
                continue
            # Keep the maximum (latest) ts per hook. ts is ISO8601
            # string-comparable; no parsing needed for the max.
            if h not in last_fired or ts > last_fired[h]:
                last_fired[h] = ts
with open(registry_path, encoding="utf-8") as f:
    reg = json.load(f)
sensors = reg.get("sensors", [])
out = []
for s in sensors:
    name = s["name"]
    lf = last_fired.get(name)
    if lf is None:
        ds = None
    else:
        # days_silent = floor((now - last_fired) / 1 day). ISO8601
        # string sort order matches chronological order, but use
        # datetime subtraction for the day count to be safe across
        # fractional seconds and tz variants in the journal stream.
        try:
            lf_dt = dt.datetime.fromisoformat(lf.replace("Z", "+00:00"))
            ds = (now - lf_dt).days
        except ValueError:
            ds = None
    out.append({
        "name": name,
        "should_fire_when": s.get("should_fire_when"),
        "max_silent_days": s.get("max_silent_days"),
        "fallback_role": s.get("fallback_role"),
        "must_fire_in_session": s.get("must_fire_in_session", False),
        "enabled": s.get("enabled", True),
        "last_fired": lf,
        "days_silent": ds,
    })
# Stable order for the consumer (HOOK-1 hashes the stale set, see Q4 in
# docs/research/sensor-staleness-notifier-design.md). Sort by name.
out.sort(key=lambda e: e["name"])
print(json.dumps(out, separators=(",", ":")))
PY
  exit 0
fi

# Source the shared libraries.
# shellcheck source=../../_lib/frontmatter-helpers.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../_lib/frontmatter-helpers.sh"
# shellcheck source=../../_lib/err.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../_lib/err.sh"

# Fail loud (Rule 12): if the resolved root holds none of the fleet dirs, root
# resolution failed — error out instead of a false-clean "0 artifacts" pass. A
# post-extraction dotfiles root legitimately has only hooks/; that still counts.
if [ ! -d "$CLAUDE_DIR/agents" ] && [ ! -d "$CLAUDE_DIR/skills" ] && \
   [ ! -d "$CLAUDE_DIR/commands" ] && [ ! -d "$CLAUDE_DIR/hooks" ]; then
  err_die "no harness fleet (agents/skills/commands/hooks) under: $CLAUDE_DIR — pass the repo root explicitly: bash audit.sh <repo-root>"
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
# --plugin-cache <path> overrides the default for testing (see tests/harness-audit/fixtures/).
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

# Finding IDs reuse the per-tier counters (F<n>/W<n>/I<n>). The previous
# next_id() helper incremented its counter inside a $(...) command substitution
# (a subshell), so the parent counter never advanced and every finding rendered
# as F1/W1/I1. Folding the increment into the same assignment that already
# tracks the exit-code totals keeps IDs unique per tier with no subshell.
crit() { CRIT_COUNT=$((CRIT_COUNT + 1)); echo "  CRIT F${CRIT_COUNT}: $1"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); echo "  WARN W${WARN_COUNT}: $1"; }
info() { INFO_COUNT=$((INFO_COUNT + 1)); echo "  INFO I${INFO_COUNT}: $1"; }

# ── helpers (fm_get / fm_has / SKIP_SCAFFOLD_GLOB come from _lib/frontmatter-helpers.sh) ──

# Run a find-like command and return its match count; if the starting directory
# is missing (find exits 1) we still get "0" instead of tripping set -e/pipefail.
safe_count() {
  local n
  n=$({ "$@" 2>/dev/null || true; } | wc -l | tr -d ' ')
  printf '%s' "$n"
}

# ── main ─────────────────────────────────────────────────────────────

echo "=== Skill Audit Report ==="
echo "Root: $REPO_ROOT"

# 1. Fleet count
AGENTS=$(safe_count find "$CLAUDE_DIR/agents" -maxdepth 1 -name '*.md' -type f)
SKILLS=$(safe_count find "$CLAUDE_DIR/skills" -maxdepth 1 -type d -not -name '_*' -not -name 'skills')
COMMANDS=$(safe_count find "$CLAUDE_DIR/commands" -maxdepth 1 -name '*.md' -type f)
HOOKS=$(safe_count find "$CLAUDE_DIR/hooks" -type f \( -name '*.sh' -o -name '*.py' \) -not -path '*__pycache__*' -not -name '_*')
OUTPUT_STYLES=$(safe_count find "$CLAUDE_DIR/output-styles" -maxdepth 1 -name '*.md' -type f)
THEMES=$(safe_count find "$CLAUDE_DIR/themes" -maxdepth 1 -name '*.json' -type f)
echo "Fleet: ${AGENTS:-0} agents, ${SKILLS:-0} skills, ${COMMANDS:-0} commands, ${HOOKS:-0} hooks, ${OUTPUT_STYLES:-0} output-styles, ${THEMES:-0} themes"
# Header context, NOT a finding: a plugin cache always exists for the owner who
# dogfoods the plugin, so this fires every run and is never actionable. An
# always-on non-actionable "finding" is noise in the findings channel — print it
# as a context line alongside Root:/Fleet: instead (keeps 0C/0W/0I honest).
if [ "$PLUGIN_ACTIVE" -eq 1 ]; then
  echo "Plugin cache: $PLUGIN_CACHE (F1 treats plugin-delivered components as loadable)"
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

# 3. Symlink integrity — hooks (recurse: hooks live in gates/, advisory/, …)
# globstar with set -e exits if the directory is empty and the pattern expands
# literally to itself; use find so empty/minimal fixtures don't kill the audit.
if [ -d "$CLAUDE_DIR/hooks" ]; then
  while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    case "${f#"$CLAUDE_DIR"/hooks/}" in tests/*|*__pycache__*) continue;; esac
    name=$(basename "$f")
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
  done < <(find "$CLAUDE_DIR/hooks" -type f -not -path '*__pycache__*' -print0 2>/dev/null || true)
fi

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
  if [ -z "$(fm_get "$f" "name" --block)" ]; then
    crit "command '$name' missing name: in frontmatter"
  fi
  # NOTE: a `type: command` frontmatter requirement was retired 2026-06-16 — it
  # was self-referential (the field existed only to satisfy this check; nothing
  # functional read it, it is not in the official slash-command schema, and the
  # commands/ directory already determines command-ness). See CLAUDE.md
  # "disable-model-invocation — selection criterion" note.
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
  for f in "$CLAUDE_DIR/hooks"/**/*; do
    [ -f "$f" ] || continue
    case "${f#"$CLAUDE_DIR"/hooks/}" in tests/*|*__pycache__*) continue;; esac
    hook_name=$(basename "$f")
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
  done < <(grep -oE '\([^)]+\.md\)' "$MEMORY_INDEX" | tr -d '()' | sort -u || true)
fi

# 14. PyCache tracked by git
if git -C "$REPO_ROOT" ls-files | grep -q '__pycache__\|\.pyc$'; then
  crit "__pycache__ or *.pyc tracked by git (should be .gitignore'd)"
fi

# 15. settings.json delivery mode — context, NOT a finding. In the single
# plugin-delivery path (ADR 0001) settings.json carries only `hooks`; the
# commands/agents/skills arrays are absent BY DESIGN (loaded from the plugin
# cache). That's permanent, not drift, so a missing array fires every run and
# is never actionable — same shape as the demoted F1/plugin-cache line. Print
# it as context alongside Root:/Fleet:, don't emit info() noise.
if [ -f "$SETTINGS" ]; then
  _missing=""
  for _k in commands agents skills; do
    python3 -c "import json,sys; d=json.load(open('$SETTINGS')); sys.exit(0 if '$_k' in d else 1)" 2>/dev/null || _missing="$_missing $_k"
  done
  [ -n "$_missing" ] && echo "settings.json delivery: arrays absent ($_missing ) — loaded via plugin cache / ~/.claude directly"
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
done < <(find "$CLAUDE_DIR/skills" -name '*.py' -not -path '*__pycache__*' 2>/dev/null || true)

# 18. Bundled shell scripts pass syntax check
while IFS= read -r f; do
  if ! bash -n "$f" 2>/dev/null; then
    crit "bundled script '${f#$CLAUDE_DIR/}' has a shell syntax error"
  fi
done < <(find "$CLAUDE_DIR/skills" -name '*.sh' 2>/dev/null || true)

# 19. Bundled JSON files parse
while IFS= read -r f; do
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    crit "bundled JSON '${f#$CLAUDE_DIR/}' is invalid"
  fi
done < <(find "$CLAUDE_DIR/skills" -name '*.json' 2>/dev/null || true)

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

# 20.5. Duplicate-surface detector — two surfaces sharing the SAME name: AND a
# near-identical description are a true content twin (the kbg-help skill+command
# dup, removed v0.2.66). Same name with DISTINCT descriptions is a legitimate
# skill↔command twin (e.g. ideate) — NOT flagged. Keys on name to stay
# false-positive-free; similarity is computed via python difflib on the
# description bodies. Fires on ratio ≥ 0.85 OR a ≥ 60-char identical run (a
# copy-pasted "Don't use for…" tail), which the closest-match-wins-wrong
# routing failure (code.claude.com/docs/en/skills) is born from. WARN, not CRIT:
# an intentional twin pair that drifts into similarity is a routing smell, not a
# build-breaker.
_dup_tsv=$(mktemp)
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/agents"/*.md "$CLAUDE_DIR/commands"/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  label=$(basename "$f" .md); [ "$label" = "SKILL" ] && label=$(basename "$(dirname "$f")")
  nm=$(fm_get "$f" "name")
  [ -n "$nm" ] || continue
  dsc=$(fm_get "$f" "description" --block | tr '\n\t' '  ')
  printf '%s\t%s\t%s\n' "$nm" "$label" "$dsc" >> "$_dup_tsv"
done
while IFS= read -r finding; do
  [ -n "$finding" ] && warn "$finding"
done < <(python3 - "$_dup_tsv" <<'PYEOF'
import sys, difflib
from collections import defaultdict
groups = defaultdict(list)
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3:
            continue
        groups[parts[0]].append((parts[1], parts[2]))
for name, surfaces in groups.items():
    for i in range(len(surfaces)):
        for j in range(i + 1, len(surfaces)):
            (la, da), (lb, db) = surfaces[i], surfaces[j]
            sm = difflib.SequenceMatcher(None, da, db)
            ratio = sm.ratio()
            longest = sm.find_longest_match(0, len(da), 0, len(db)).size
            if ratio >= 0.85 or longest >= 60:
                print(f"duplicate surface: name '{name}' shared by {la} + {lb} "
                      f"({int(ratio*100)}% identical, {longest}-char shared run) "
                      f"— delete one or differentiate the descriptions")
PYEOF
)
rm -f "$_dup_tsv"

# 21. Agent model value — must be a documented alias or a full claude-* model ID.
# code.claude.com/docs/en/model-config: aliases sonnet|opus|haiku|fable|inherit,
# or a full ID (claude-opus-4-8, claude-sonnet-4-6, ...). model is optional
# (defaults to inherit), so a missing field is fine — only a present-but-bogus
# value warns.
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  model=$(fm_get "$f" "model" --block)
  [ -n "$model" ] || continue
  case "$model" in
    sonnet|opus|haiku|fable|inherit) ;;
    claude-*) ;;
    *) warn "agent '$name' model='$model' is not an alias (sonnet|opus|haiku|fable|inherit) or a claude-* ID" ;;
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
VALID_TOOLS="Agent Bash CronCreate CronDelete CronList Edit EnterWorktree ExitWorktree Glob Grep LSP ListMcpResourcesTool Monitor NotebookEdit PowerShell PushNotification Read ReadMcpResourceTool RemoteTrigger SendMessage ShareOnboardingGuide Skill TaskCreate TaskGet TaskList TaskStop TaskUpdate ToolSearch WebFetch WebSearch Workflow Write"
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
  # [!_]*/ skips _-prefixed scaffolds (e.g. _template). Guard each loop with
  # an if so the command group ends with exit 0 even when the directory is
  # missing; with set -euo pipefail the pipeline would otherwise abort here.
  if [ -d "$CLAUDE_DIR/skills" ]; then
    for d in "$CLAUDE_DIR/skills"/[!_]*/; do [ -d "$d" ] && basename "$d"; done
  fi
  if [ -d "$HOME/.claude/skills" ]; then
    for d in "$HOME/.claude/skills"/[!_]*/; do [ -d "$d" ] && basename "$d"; done
  fi
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
  done < <(grep -E '^@[^[:space:]]' "$cmd" 2>/dev/null || true)
done < <(find "$REPO_ROOT" -name 'CLAUDE.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null || true)

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
  \) -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null || true)

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
for f in "$CLAUDE_DIR/hooks"/**/*.sh; do
  [ -f "$f" ] || continue
  case "${f#"$CLAUDE_DIR"/hooks/}" in tests/*|*__pycache__*) continue;; esac
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
  while IFS= read -r -d '' f; do EVAL_TARGETS+=("$f"); done < <(find "$REPO_ROOT/tests/evals/skills" -type f -name 'evals.json' -print0 2>/dev/null || true)
  while IFS= read -r -d '' f; do EVAL_TARGETS+=("$f"); done < <(find "$REPO_ROOT/scripts" -maxdepth 2 -type f -name 'run-baseline-eval.py' -print0 2>/dev/null || true)
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

# 32. Autonomy invariant guardrail — round-2 drill-down (2026-06-12),
# surface-closure 2026-06-16. ADR 0002 names FIVE load-bearing surfaces for the
# invariant; before this closure only surface 3 (the `disable-model-invocation:
# true` frontmatter on recursive-improve) was guarded — and even that silently
# passed when the skill file was deleted (delete the skill -> the guard no-ops
# -> the invariant is unprotected with no flag raised). Surfaces 1/2/4 (the
# prose homes in CONTEXT.md, METHODOLOGY.md, harness-decay-cadence.md) had no
# check at all and could be reworded or removed silently.
#
# Trigger: a repo DECLARES the invariant iff docs/adr/0002-autonomy-invariant.md
# exists. When it does, the self-binding skill must EXIST (not merely match-when-
# present) and every doc surface must keep its load-bearing phrase. When ADR 0002
# is absent (other plugin repos, the audit fixtures) the whole block is skipped —
# the invariant is THIS repo's, not a universal plugin requirement.
#
# Phrase matches are exact (grep -qF) on a single contiguous line, each the most
# invariant-specific wording on its surface, so a careless reword trips the gate.
# If this check fires on a real repo the invariant has regressed and the harness
# is one model-version from self-rewriting — CRIT, not WARN.
#
# Two triggers, deliberately split: surface 3 (the frontmatter flag) is checked
# whenever the skill is PRESENT — this preserves the original guard for any repo
# carrying the skill, regardless of ADR. The deleted-skill hole and the doc
# surfaces 1/2/4 are checked only when the repo DECLARES the invariant (ADR 0002
# present), because absence-as-regression and the prose homes are meaningful
# only for this harness, not every plugin repo that happens to vendor the skill.
RI_SKILL="$CLAUDE_DIR/skills/recursive-improve/SKILL.md"
ADR0002="$CLAUDE_DIR/docs/adr/0002-autonomy-invariant.md"
if [ -f "$RI_SKILL" ]; then
  # Surface 3: present skill must carry the flag in its FRONTMATTER. Read it via
  # fm_get (which parses ONLY the `---` block) rather than the old `head -20 |
  # grep -qF` — the exact phrase "disable-model-invocation: true" also appears in
  # the skill's PROSE (the autonomy-invariant paragraph + the L3 note), so both a
  # line-window grep AND a naive grep-anywhere could pass with the real frontmatter
  # flag deleted. fm_get is frontmatter-anchored AND line-count-independent (a
  # docstring rewrite that pushes the flag past line 20 can no longer break it).
  if [ "$(fm_get "$RI_SKILL" "disable-model-invocation" --block | tr -d ' ')" != "true" ]; then
    crit "skills/recursive-improve/SKILL.md: missing 'disable-model-invocation: true' in frontmatter (autonomy invariant regressed — see CONTEXT.md §Invariants + ADR 0002)"
  fi
elif [ -f "$ADR0002" ]; then
  # Deleted-skill hole: ADR declares the invariant but the self-binding skill is
  # gone — deleting it silently no-opped the old guard. That deletion IS the regression.
  crit "autonomy invariant: ADR 0002 present but skills/recursive-improve/SKILL.md is MISSING — deleting the self-binding skill no-ops the guard (ADR 0002 surface 3)"
fi
if [ -f "$ADR0002" ]; then
  # Surfaces 1/2/4: each doc surface must exist and keep its load-bearing phrase.
  while IFS='|' read -r _label _rel _phrase; do
    [ -n "$_label" ] || continue
    _f="$CLAUDE_DIR/$_rel"
    if [ ! -f "$_f" ]; then
      crit "autonomy invariant: ADR 0002 present but $_rel is MISSING ($_label — ADR 0002)"
    elif ! grep -qF "$_phrase" "$_f"; then
      crit "autonomy invariant: $_rel dropped its load-bearing phrase \"$_phrase\" ($_label — ADR 0002)"
    fi
  done <<'AUTONOMY_SURFACES'
surface 1 CONTEXT §Invariants|CONTEXT.md|unattended self-repair loop
surface 2 METHODOLOGY Rule 4|METHODOLOGY.md|every loop terminates at a human gate
surface 4 decay-cadence|docs/harness-decay-cadence.md|autonomous self-rewriter
AUTONOMY_SURFACES
fi

# 33. Skill description injection-risk + imperative-intensity scan.
# Checks that no SKILL.md description: field contains prompt-injection patterns
# (override instructions, persona hijack, system-prompt escape attempts).
# Also emits INFO if description: > 500 chars (harder to audit, injection risk rises)
# and INFO if description: uses over-forceful imperatives (ALWAYS/CRITICAL/MUST/
# "if in doubt") — Opus 4.8+ over-triggers on older-model intensity; the doc fix is
# plain "Use when …" trigger phrasing (Anthropic prompting-Opus-4.8 guidance, 2026-06).
# Fires WARNING if injection patterns found; INFO for length/imperative — never CRIT
# (de-escalation is a judgment call: some ALWAYS/MUST triggers are load-bearing).
INJECTION_PATTERNS='(ignore (previous|prior|all) instruction|disregard (all|previous)|forget (everything|all)|you are now|act as if you|<system>|<\/system>|<user>|<\/user>|SYSTEM PROMPT|override your)'
IMPERATIVE_PATTERNS='\b(ALWAYS|CRITICAL|MUST)\b|[Ii]f in doubt|[Dd]efault to using'
desc_inj_issues=0
for f in "$CLAUDE_DIR/skills"/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  skill_name=$(basename "$(dirname "$f")")
  desc=$(fm_get "$f" "description" --block)
  [ -z "$desc" ] && continue
  if printf '%s' "$desc" | /usr/bin/grep -iEq "$INJECTION_PATTERNS"; then
    warn "skill '$skill_name' description: contains potential injection pattern — review manually"
    desc_inj_issues=$((desc_inj_issues + 1))
  fi
  if printf '%s' "$desc" | /usr/bin/grep -Eq "$IMPERATIVE_PATTERNS"; then
    info "skill '$skill_name' description: over-forceful imperative (ALWAYS/CRITICAL/MUST/'if in doubt') — Opus 4.8+ over-triggers; prefer 'Use when …'"
  fi
done
# No output on clean — crit/warn/info only when there's an issue (audit.sh convention)

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
# `version` field is older than 30 days (hardcoded in _check_plugin_version
# below) AND has no sibling `last_reviewed:` / `last_reviewed_reason:`
# justification. Emit crit if the file does not parse as JSON or
# `version` is missing. Defense in depth: claude plugin validate
# already enforces the JSON shape, but a missing `version` is the
# specific failure mode that breaks the cache-resolver at audit.sh:73.
# Sub-check 31.3 — settings.json permission re-audit bookmark: per
# decay-cadence §Permission re-audit, the kbg-harness equivalent is
# a `## Permission re-audit` section with a `last_permission_review:
# YYYY-MM-DD` marker in `docs/harness-decay-cadence.md`. Emit info if
# the marker is older than 90 days (PERM_MAX_AGE, hardcoded;
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
      PLUGIN_PARSE_FAIL)     crit "schema-rot: $(basename "$payload" 2>/dev/null || echo "$payload") failed to parse as JSON" ;;
      PLUGIN_NO_VERSION)     crit "schema-rot: $(basename "$payload" 2>/dev/null || echo "$payload") has no 'version' field (cache-resolver will break)" ;;
      PLUGIN_STALE)          info "schema-rot: $payload — consider a version bump (30d cadence per decay-cadence)" ;;
      PERM_BOOKMARK_MISSING) info "schema-rot: $payload — add a 'last_permission_review:' marker (quarterly cadence per decay-cadence)" ;;
      PERM_BOOKMARK_BAD)     warn "schema-rot: permission re-audit marker date is unparseable: $payload" ;;
      PERM_BOOKMARK_STALE)   info "schema-rot: permission re-audit $payload" ;;
      HOOKS_PARSE_FAIL)      crit "schema-rot: hooks.json failed to parse: $payload" ;;
      HOOKS_SHAPE_FAIL)      crit "schema-rot: hooks.json — $payload" ;;
      HOOKS_SHAPE_WARN)      warn "schema-rot: hooks.json — $payload" ;;
    esac
  done < <(python3 - "$CLAUDE_DIR" "$REPO_ROOT" <<'PY' 2>/dev/null
import datetime as dt, json, os, re, sys
claude_dir, repo_root = sys.argv[1], sys.argv[2]
today = dt.date.today()

# 31.1 RETIRED 2026-06-16 — the "every SKILL.md must carry ## Input Contract /
# ## Output Format / ## Failure Modes" requirement was a self-referential blanket:
# a presence-only check (substring of three headings, never content) that 29/37
# skills satisfied with byte-identical boilerplate from an unreferenced generator
# (scripts/utils/add-canonical-sections.py, now deleted). Nothing functional read
# the sections beyond this check; it manufactured the schema-rot it claimed to
# police (same shape as the retired `type: command`). The real per-skill contract
# survives where a skill actually has one; it is no longer mandated fleet-wide.

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
                        hook_type = h.get("type")
                        if not isinstance(hook_type, str) or not hook_type.strip():
                            print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].type: missing/empty")
                            continue
                        # Validate required fields per hook type (Claude Code hook schema).
                        if hook_type == "command":
                            if not isinstance(h.get("command"), str) or not h["command"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].command: missing/empty")
                        elif hook_type == "http":
                            if not isinstance(h.get("url"), str) or not h["url"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].url: missing/empty")
                        elif hook_type == "mcp":
                            if not isinstance(h.get("server"), str) or not h["server"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].server: missing/empty")
                            if not isinstance(h.get("tool"), str) or not h["tool"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].tool: missing/empty")
                        elif hook_type == "agent":
                            if not isinstance(h.get("agent"), str) or not h["agent"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].agent: missing/empty")
                        elif hook_type == "prompt":
                            if not isinstance(h.get("prompt"), str) or not h["prompt"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].prompt: missing/empty")
                        else:
                            # Unknown type is not a hard failure today; emit a warning shape entry.
                            print(f"HOOKS_SHAPE_WARN\t{event_name}[{gi}].hooks[{hi}].type: unknown hook type '{hook_type}'")
PY
)
else
  warn "schema-rot check skipped — python3 unavailable"
fi

# 34. Autonomy invariant — surface 5: inferential-FB sensors are advisory-only
# and must NEVER emit a permissionDecision (ADR 0002 + CLAUDE.md "advisory only"
# invariant). Check #29 catches a hook that BOTH journals AND decides; it does
# NOT catch an inferential-FB sensor that gates WITHOUT journaling — that hook
# would slip #29 yet still be a model-driven mutation gate (covert L4). This
# check closes that gap: read sensors.json for fallback_role=="inferential-FB",
# resolve each sensor name to its hook script (basename starts with the name),
# strip full-line comments (a comment mentioning the invariant is fine), and
# CRIT if the code emits a decision (raw permissionDecision key, the _lib
# hook_decision emitter, or kbg_permission_decision). Hermetic: gated on
# sensors.json + jq presence, so non-kbg plugin repos skip cleanly.
SENSORS_JSON="$CLAUDE_DIR/hooks/sensors.json"
if [ -f "$SENSORS_JSON" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r _sname; do
    [ -n "$_sname" ] || continue
    _hook=$(find "$CLAUDE_DIR/hooks" -type f -name "${_sname}*" 2>/dev/null | grep -E '\.(sh|py)$' | head -1)
    [ -n "$_hook" ] || continue
    if grep -vE '^[[:space:]]*#' "$_hook" 2>/dev/null | grep -qE 'permissionDecision|hook_decision|kbg_permission_decision'; then
      crit "autonomy invariant: inferential-FB sensor '$_sname' (${_hook#"$CLAUDE_DIR"/}) emits a permissionDecision in code — advisory sensors must journal, not gate (ADR 0002 surface 5 + CLAUDE.md 'advisory only')"
    fi
  done < <(jq -r '.sensors[] | select(.fallback_role=="inferential-FB") | .name' "$SENSORS_JSON" 2>/dev/null || true)
fi

# 35. disable-model-invocation must carry a documented reason (DETERMINISTIC).
# The flag is a per-surface judgment (CLAUDE.md selection criterion); a flag
# WITHOUT a recorded reason is an undocumented decision — and in practice the
# audit found these were often dir-of-origin residue ("all commands flagged")
# rather than a real per-surface call. This is a presence check (NOT a semantic
# judge): every `disable-model-invocation: true` surface must also carry a
# non-empty `disable-model-invocation-reason:`. It HAS teeth (any unreasoned flag
# WARNs and can fail) — unlike the prior reporter-shape heuristic it replaced,
# which matched zero real flagged surfaces (a Rule-9 test that could not fail).
# Appropriateness stays semantic + advisory (human review of the reasons); this
# check only enforces that the reason EXISTS, which is deterministic. WARN (not
# CRIT): a missing reason is a doc gap, not a safety regression — the one
# safety-load-bearing flag (recursive-improve) is CRIT-guarded by #32.
for f in "$CLAUDE_DIR/commands"/*.md "$CLAUDE_DIR/skills"/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  head -20 "$f" | grep -qF 'disable-model-invocation: true' || continue
  _nm=$(basename "$f" .md); case "$f" in */SKILL.md) _nm=$(basename "$(dirname "$f")") ;; esac
  if [ -z "$(fm_get "$f" "disable-model-invocation-reason" --block)" ]; then
    warn "'$_nm': disable-model-invocation: true without a 'disable-model-invocation-reason:' — record WHY this surface is user-only (per-surface, not blanket; CLAUDE.md selection criterion)"
  fi
done

# 36. ideate skill — structural contract (PR2 of ideate-adhd-port). The
# skill is a 2-wave fan-out port from upstream ADHD (docs/research/kbg-vs-adhd.md).
# The structural contract must hold or the next refactor will silently
# collapse the algorithm (the 2026-06-12 44→105-agent failure mode that
# bounded-agent-spawning.md was written to prevent). WARNs (not CRITs) on
# missing pieces: the skill is supposed to have all of them, but a WARN
# surfaces without blocking the audit. The regression fixture
# eval/regressions/ideate-fanout-cap.json is the load-bearing guard;
# this check is the inline fallback for editor / pre-commit visibility.
IDEATE_SKILL="$CLAUDE_DIR/skills/ideate/SKILL.md"
if [ -f "$IDEATE_SKILL" ]; then
  if [ -z "$(fm_get "$IDEATE_SKILL" "name" --block)" ]; then
    warn "ideate skill missing 'name:' in frontmatter"
  elif [ "$(fm_get "$IDEATE_SKILL" "name" --block | tr -d ' ')" != "ideate" ]; then
    warn "ideate skill frontmatter name mismatch"
  fi
  if [ "$(fm_get "$IDEATE_SKILL" "disable-model-invocation" --block | tr -d ' ')" != "false" ]; then
    warn "ideate skill must have disable-model-invocation: false (user opted in to auto-fire on vague open-ended prompts; F8.5 orchestrate is the actual cap)"
  fi
  for sec in "## Pre-flight gate" "## Phase 1" "## Phase 2" "## Frames table" "## 3-axis scoring rubric" "## Isolation invariant"; do
    if ! /usr/bin/grep -qF "$sec" "$IDEATE_SKILL"; then
      warn "ideate skill missing required section: $sec (PR2 contract; locks the 2-wave algorithm shape)"
    fi
  done
else
  warn "skills/ideate/SKILL.md missing — ideate port not landed"
fi

# 37. DOMAINS.md `## Path → Context` ≡ orchestrator-nudge.sh PATH_PATTERNS.
# Both encode the SAME path→routing-label map; DOMAINS.md and the hook's "SYNC:"
# comment each assert they stay in lockstep, but nothing enforced it — and they
# HAD drifted (the entire Integration group + several role assignments were
# missing from the doc). The hook is the executor (source of truth); this check
# verifies the doc table mirrors it token-for-token. Same class as #12/#16 (doc
# must track code) → WARN. Deterministic set-equality on `token|Label` pairs.
# Hermetic: skips if either file is absent. The label whitelist anchors the
# hook-side grep so only real PATH_PATTERNS pair lines match (no block parsing).
DOMAINS_MD="$CLAUDE_DIR/DOMAINS.md"
NUDGE_SH="$CLAUDE_DIR/hooks/advisory/orchestrator-nudge.sh"
if [ -f "$DOMAINS_MD" ] && [ -f "$NUDGE_SH" ]; then
  _labels='Execution|Implementation|Orchestration|Quality|Communication|Emergency|Integration|doctrine|infra|docs'
  _pp=$(grep -E "^[A-Za-z._][^| ]*\|(${_labels})\$" "$NUDGE_SH" 2>/dev/null | sort -u)
  _dm=$(awk -F'|' '/^## Path . Context/{f=1;next} f&&/^## /{exit} f&&/^\|/&&/`/{
    label=$3; gsub(/^[ \t]+|[ \t]+$/,"",label);
    n=split($2,a,"`");
    for(i=2;i<=n;i+=2){t=a[i]; gsub(/^[ \t]+|[ \t]+$/,"",t); if(t!="") print t"|"label}
  }' "$DOMAINS_MD" 2>/dev/null | sort -u)
  if [ "$_pp" != "$_dm" ]; then
    # `|| true`: diff exits 1 on differences (always, in this branch) — without
    # the guard `set -euo pipefail` aborts before the warn fires (same latent
    # bug fixed in #41). Was dormant: this seam is normally aligned.
    _d=$(diff <(printf '%s\n' "$_pp") <(printf '%s\n' "$_dm") | tr '\n' ' ' | cut -c1-280 || true)
    warn "DOMAINS.md '## Path → Context' out of sync with orchestrator-nudge.sh PATH_PATTERNS (hook is source of truth) — diff (< hook, > doc): $_d"
  fi
fi

# 38. dismiss-stale.md Q3 mirror ≡ notify-sensor-staleness.sh gate. The command
# duplicates the hook's is_stale/is_must_fire_stale/role-classification gate AND
# the Q3 trigger thresholds verbatim (a SYNC-WITH comment is the only seam). It
# DRIFTED once: the hook's null-branch was fixed to `return s.get("observable",
# True)` while the command kept `return True`, so the two computed different stale
# sets and the dismissal hash never matched (a silent no-op the operator hit on
# /dismiss-stale). This asserts the full set of load-bearing gate lines — both the
# classification (is_stale/must_fire) AND the trigger thresholds (1 enforcement /
# ≥3 advisory / ≥1 must_fire) — appear in BOTH files (whitespace-normalized,
# substring). WARN.
DSM="$CLAUDE_DIR/commands/dismiss-stale.md"
NSS="$CLAUDE_DIR/hooks/maintenance/notify-sensor-staleness.sh"
if [ -f "$DSM" ] && [ -f "$NSS" ]; then
  _nss_n=$(tr -s ' \t' ' ' < "$NSS")
  _dsm_n=$(tr -s ' \t' ' ' < "$DSM")
  while IFS= read -r _sig; do
    [ -n "$_sig" ] || continue
    if printf '%s' "$_nss_n" | grep -qF "$_sig" && ! printf '%s' "$_dsm_n" | grep -qF "$_sig"; then
      warn "dismiss-stale.md Q3 mirror missing gate line present in notify-sensor-staleness.sh: '$_sig' — the two MUST stay in sync (commands/dismiss-stale.md SYNC-WITH seam)"
    fi
  done <<'SIGS'
return s.get("observable", True)
return ds > thr
return ds is not None and ds >= 1
enforcement_roles = {"computational-FF", "computational-FB"}
advisory_roles = {"inferential-FF", "inferential-FB"}
len(enforcement_stale) >= 1
or len(advisory_stale) >= 3
or len(must_fire_stale) >= 1
SIGS
fi

# 39. Orphan sensor — every name in hooks/sensors.json must resolve to a real
# hook script. A sensor whose hook was renamed/removed lingers as a phantom and
# makes the staleness monitor (notify-sensor-staleness.sh) report a false 'never
# fired' for a sensor that no longer exists. Generalizes the sensor→file
# resolution #34 already does for inferential-FB. Allowlist-free + deterministic
# → WARN. (The inverse — a journaling hook with no sensor entry — is deliberately
# NOT guarded: it needs a hand-maintained allowlist of non-sensor hooks, itself a
# drift seam. #34 + this cover the load-bearing direction.)
SENSORS_JSON="$CLAUDE_DIR/hooks/sensors.json"
if [ -f "$SENSORS_JSON" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r _sname; do
    [ -n "$_sname" ] || continue
    _hk=$(find "$CLAUDE_DIR/hooks" -type f -name "${_sname}*" 2>/dev/null | grep -E '\.(sh|py)$' | head -1)
    if [ -z "$_hk" ]; then
      warn "sensor '$_sname' in sensors.json has no matching hook script under hooks/ (orphan — staleness monitor will report false 'never fired')"
    fi
  done < <(jq -r '.sensors[].name' "$SENSORS_JSON" 2>/dev/null || true)
fi

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

# 42. Reasoning-models index drift — the unified 39-model table in
# docs/reference/reasoning-models.md must list one row for every vendored
# thinking-*/SKILL.md directory under docs/reference/thinking-skills/skills/.
# A mismatch means a model was added/removed/renamed without updating the catalog.
# Mapping rule: upstream keeps the same hyphen-separated tokens, but moves a
# trailing `-thinking` to the front as the `thinking-` prefix. So
# `systems-thinking` → `thinking-systems`, while `feedback-loops` simply becomes
# `thinking-feedback-loops`.
RM_INDEX="$CLAUDE_DIR/docs/reference/reasoning-models.md"
RM_SKILLS_DIR="$CLAUDE_DIR/docs/reference/thinking-skills/skills"
if [ -f "$RM_INDEX" ] && [ -d "$RM_SKILLS_DIR" ]; then
  _rm_drift=$(python3 - "$RM_INDEX" "$RM_SKILLS_DIR" <<'PY'
import os, re, sys
index_path, skills_dir = sys.argv[1:3]

in_index = False
rows = set()
with open(index_path) as fh:
    for line in fh:
        if line.startswith('## Unified 39-model index'):
            in_index = True
            continue
        if not in_index:
            continue
        # Stop parsing when we leave the index section; downstream tables are
        # commentary/mapping tables, not part of the 39-model catalog.
        if line.startswith('## '):
            in_index = False
            continue
        if not line.startswith('|') or line.lstrip().startswith('|--') or ' Model ' in line:
            continue
        row = line.split('|')[1].strip().lower()
        # Skip the separator row and any malformed entries.
        if not row or row.startswith('---') or not re.fullmatch(r'[a-z0-9\-]+', row):
            continue
        rows.add(row)

dirs = {entry for entry in os.listdir(skills_dir)
        if os.path.isdir(os.path.join(skills_dir, entry)) and entry.startswith('thinking-')}

def row_to_dir(row):
    if row.endswith('-thinking'):
        return 'thinking-' + row[:-9]
    return 'thinking-' + row

missing_dirs = sorted(row_to_dir(r) for r in rows if row_to_dir(r) not in dirs)
orphan_dirs = sorted(d for d in dirs
                     if (d[len('thinking-'):] not in rows)
                     and ((d[len('thinking-'):] + '-thinking') not in rows))
if missing_dirs or orphan_dirs:
    msg = []
    if missing_dirs:
        msg.append(f"catalog rows with no vendored dir: {missing_dirs}")
    if orphan_dirs:
        msg.append(f"vendored dirs with no catalog row: {orphan_dirs}")
    print('; '.join(msg))
PY
)
  if [ -n "${_rm_drift:-}" ]; then
    warn "reasoning-models index drift — $_rm_drift"
  fi
else
  warn "reasoning-models reference docs missing from plugin cache: $RM_INDEX or $RM_SKILLS_DIR"
fi

# 43. L3 cage integrity (ADR 0003) — the cage-denylist + its guard are the single
# code-level bound on an unattended L3 run. If the cage is empty/missing, the guard
# is gone, or the cage stops covering a load-bearing safety surface, the loop could
# edit its own gates/audit/gauntlet and escape. Gated on ADR 0003 presence (other
# plugin repos + the audit fixtures don't declare L3, so the whole block is skipped).
# CRIT, not WARN: a holed cage is one model-version from a self-rewriting loop.
ADR0003="$CLAUDE_DIR/docs/adr/0003-l3-bounded-autonomy.md"
CAGE="$CLAUDE_DIR/scripts/l3-cage.txt"
GUARD="$CLAUDE_DIR/scripts/l3-loop-guard.py"
if [ -f "$ADR0003" ]; then
  # 43a: cage file present + non-empty (after stripping comments/blanks).
  if [ ! -f "$CAGE" ]; then
    crit "L3 cage missing: scripts/l3-cage.txt absent but ADR 0003 declares L3 (the loop would run uncaged — ADR 0003 §Three rails)"
  elif [ -z "$(grep -vE '^[[:space:]]*(#|$)' "$CAGE")" ]; then
    crit "L3 cage empty: scripts/l3-cage.txt has no entries — a deny-by-default cage with nothing in it denies nothing (fail-closed expects entries)"
  else
    # 43b: cage must cover the load-bearing anchors. A new gate hook is auto-covered
    # by hooks/** etc., so this is a small FIXED anchor set, not a per-file list.
    # _CAGE_ANCHORS is the SINGLE source for the curated anchor set: #43b checks
    # anchors⊆cage (directional), and #43d checks the L4 members are in BOTH
    # surfaces (bidirectional — a one-sided add silently un-cages a path, design
    # §5 F2/F3 blocker). Add a path here AND to scripts/l3-cage.txt in lockstep.
    _CAGE_ANCHORS="scripts/l3-cage.txt
scripts/l3-loop-guard.py
hooks/**
tests/hooks/runners/**
skills/harness-audit/scripts/audit.sh
skills/_lib/**
scripts/run-gauntlet.sh
eval/run-eval.py
scripts/evals/**
scripts/plan_linter/**
eval/datasets/**
eval/regressions/**
tests/evals/**
scripts/l4/**
.claude/settings.local.json
docs/adr/**
CLAUDE.md
METHODOLOGY.md
RTK.md
ACLI.md
DBGATE.md
CONTEXT.md
DOMAINS.md
.git/config
.git/hooks/**
git-hooks/**
.claude-plugin/plugin.json
.claude-plugin/marketplace.json"
    _missing=""
    while IFS= read -r _anchor; do
      [ -n "$_anchor" ] || continue
      grep -qxF "$_anchor" "$CAGE" || _missing="$_missing $_anchor"
    done <<<"$_CAGE_ANCHORS"
    if [ -n "$_missing" ]; then
      crit "L3 cage incomplete: scripts/l3-cage.txt is missing required safety anchor(s):$_missing (the loop could edit these to escape — ADR 0003 §Cage redesign)"
    fi
    # 43d: L4 cage↔anchor lockstep (design §5 F2/F3 blocker). #43b is directional
    # (anchors⊆cage), so a path added to the cage but missing from CAGE_ANCHORS
    # passes SILENTLY — the exact F2/F3 partial-landing this slice exists to
    # prevent. The L4 anchors (grading corpus + scheduler config + arming home)
    # must appear in BOTH surfaces; bidirectional check over the curated L4 set.
    for _a in 'eval/regressions/**' 'tests/evals/**' 'scripts/l4/**' '.claude/settings.local.json'; do
      _ic=0; _ia=0
      if grep -qxF "$_a" "$CAGE"; then _ic=1; fi
      if printf '%s\n' "$_CAGE_ANCHORS" | grep -qxF "$_a"; then _ia=1; fi
      if [ "$_ic$_ia" != "11" ]; then
        crit "L4 cage↔anchor drift: '$_a' in cage:$_ic / anchors:$_ia — must be in BOTH scripts/l3-cage.txt and the #43 CAGE_ANCHORS set (design §5 F2/F3; a one-sided add silently un-cages a path)"
      fi
    done
  fi
  # 43c: guard present, compiles, and its self-check passes (the matcher + fail-closed posture).
  if [ ! -f "$GUARD" ]; then
    crit "L3 guard missing: scripts/l3-loop-guard.py absent but ADR 0003 declares L3 (no code-level enforcer of the caps/cage)"
  elif command -v python3 >/dev/null 2>&1; then
    if ! python3 -m py_compile "$GUARD" 2>/dev/null; then
      crit "L3 guard broken: scripts/l3-loop-guard.py does not compile (py_compile failed)"
    elif ! python3 "$GUARD" selftest >/dev/null 2>&1; then
      crit "L3 guard selftest FAILED: scripts/l3-loop-guard.py selftest non-zero (cage matcher or fail-closed posture regressed)"
    fi
  fi
fi

# 44. L3 push-gate + git wiring (ADR 0003) — Gate 2 (push stays human-gated) is
# enforced by the l3-push-gate.sh PreToolUse hook; the git-hook gauntlet that runs
# the in-loop check is wired via core.hooksPath=git-hooks. A removed push-gate or a
# redirected hooksPath silently disables Gate 2 / the gauntlet. Gated on ADR 0003.
if [ -f "$ADR0003" ]; then
  PUSHGATE="$CLAUDE_DIR/hooks/gates/l3-push-gate.sh"
  HOOKSJSON="$CLAUDE_DIR/hooks/hooks.json"
  if [ ! -f "$PUSHGATE" ]; then
    crit "L3 push-gate missing: hooks/gates/l3-push-gate.sh absent but ADR 0003 declares L3 (Gate 2 unenforced — the loop could push its own batch)"
  elif [ -f "$HOOKSJSON" ] && ! grep -qF 'l3-push-gate.sh' "$HOOKSJSON"; then
    crit "L3 push-gate not registered: hooks/gates/l3-push-gate.sh exists but is not wired in hooks/hooks.json (the gate never fires)"
  fi
  # hooksPath sub-check: only when auditing the actual git working tree (skip for
  # the plugin cache, which has no .git, and for non-kbg repos without git-hooks/).
  if [ -d "$CLAUDE_DIR/git-hooks" ] && git -C "$CLAUDE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    _hp=$(git -C "$CLAUDE_DIR" config --local core.hooksPath 2>/dev/null || true)
    if [ "$_hp" != "git-hooks" ]; then
      crit "L3 git wiring: core.hooksPath is '${_hp:-<unset>}', expected 'git-hooks' — the gauntlet (pre-commit/pre-push) is bypassed (ADR 0003 §B computational push gate)"
    fi
  fi
fi

# 45. Reviewer read-only invariant (maker≠checker). An agent whose NAME marks it a
# reviewer/analyzer (reviewer|analyzer|analyst|hunter|critic|judge) must NOT grant
# Write or Edit: a verifier that can mutate what it reviews defeats the fresh-context
# independence maker≠checker depends on. Load-bearing at L3 (ADR 0003) — these agents
# run unattended inside the loop's Gate-2 review. The source frontmatter is read-only
# today (fix 5c06590); this is the regression guard against a future re-widening.
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  case "$name" in
    *reviewer*|*analyzer*|*analyst*|*hunter*|*critic*|*judge*) ;;
    *) continue ;;
  esac
  tools=$(fm_get "$f" "tools" --block)
  [ -n "$tools" ] || continue
  bad=""
  for t in $(printf '%s' "$tools" | tr ',' ' '); do
    case "$t" in Write|Edit|write|edit) bad="$bad $t" ;; esac
  done
  bad="${bad# }"
  if [ -n "$bad" ]; then
    crit "agent '$name' is a reviewer but grants '$bad' — read-only invariant (maker≠checker) broken; reviewers must not mutate what they review (ADR 0003 §L3 evolution)"
  fi
done

# 46. task-board-lib.sh sync-seam — orchestrate, types-first, and progressive-refine
# each ship a byte-identical copy of scripts/task-board-lib.sh. They must be copies
# (a skill's scripts/ is self-contained in the plugin cache — no cross-skill source),
# synced by hand with no machine-check, so one could drift silently. Compare every
# copy against the first and WARN on any divergence (same class as #37/#40). cmp
# (POSIX) sidesteps the BSD md5 / GNU md5sum portability split. Hermetic: skips if
# fewer than 2 copies exist (globstar set, nullglob is NOT — guard each match).
_tbl_ref=""
for lib in "$CLAUDE_DIR/skills"/*/scripts/task-board-lib.sh; do
  [ -f "$lib" ] || continue
  if [ -z "$_tbl_ref" ]; then _tbl_ref="$lib"; continue; fi
  if ! cmp -s "$_tbl_ref" "$lib"; then
    warn "task-board-lib.sh drift: '$lib' differs from '$_tbl_ref' — these copies are synced by hand and MUST stay byte-identical (sync-seam, same class as #37/#40)"
  fi
done

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

# 48. L4 F1 floor — fires under the flag AND stays byte-identical flag-off (design
# §5 #48, ADR 0004). The single-key autonomy_on() collapse is exactly the refactor
# that can regress the flag-OFF path via empty-string truthiness / a wrong default,
# so this check PROVES both directions instead of asserting them in prose. Gated on
# ADR 0004 presence. Three legs:
#   (a) armed (per-repo KBG_AUTONOMY=1) → the push gate DENIES a real git push;
#   (b) flag unset → the push gate no-ops (exit 0) as the L2 baseline;
#   (c) enumeration — every arming read routes through autonomy_on(): CRIT on a raw
#       KBG_AUTONOMY literal outside the sanctioned homes, and on any LEFTOVER legacy
#       KBG_AUTONOMY_L3 / KBG_L3_REVIEW_DONE in active code (the collapse must be
#       complete — a leftover direct read is the inert-under-L4 hole F1 closes).
ADR0004="$CLAUDE_DIR/docs/adr/0004-l4-autonomy.md"
if [ -f "$ADR0004" ]; then
  PUSHGATE48="$CLAUDE_DIR/hooks/gates/l3-push-gate.sh"
  # 48a/48b: runtime both directions. Skip cleanly if the gate or jq is absent.
  if [ -f "$PUSHGATE48" ] && command -v jq >/dev/null 2>&1; then
    _ev48='{"tool_name":"Bash","tool_input":{"command":"git push origin develop"}}'
    _ap48=$(mktemp -d)
    mkdir -p "$_ap48/.claude"
    printf '{"env":{"KBG_AUTONOMY":"1"}}' > "$_ap48/.claude/settings.local.json"
    _arm48=$(printf '%s' "$_ev48" | env KBG_AUTONOMY=1 CLAUDE_PROJECT_DIR="$_ap48" bash "$PUSHGATE48" 2>/dev/null \
             | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null) || true
    # The gate emits NO JSON when it no-ops (exit 0 early) — jq on an empty stream
    # exits 0 with empty output, so treat empty as "none" (no deny), mirroring the
    # pcheck helper in test-ch-l3.sh.
    if [ -z "$_arm48" ]; then _arm48="none"; fi
    _off48=$(printf '%s' "$_ev48" | bash "$PUSHGATE48" 2>/dev/null \
             | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null) || true
    if [ -z "$_off48" ]; then _off48="none"; fi
    # disposable mktemp fixture in $TMPDIR — trash if available (owner pref), else rm -rf.
    if command -v trash >/dev/null 2>&1; then trash "$_ap48" >/dev/null 2>&1 || rm -rf "$_ap48"; else rm -rf "$_ap48"; fi
    [ "$_arm48" = "deny" ] || crit "audit #48a: under KBG_AUTONOMY=1 (per-repo) the push gate must DENY a real git push (got '$_arm48') — the F1 hole is not closed (design §5 #48, ADR 0004)"
    [ "$_off48" = "none" ] || crit "audit #48b: with the flag unset the push gate must no-op (exit 0) as the L2 baseline (got '$_off48') — flag-OFF byte-identical regressed (design §5 #48)"
  fi
  # 48c: enumeration. Sanctioned raw-KBG_AUTONOMY homes (the helper bodies + the
  # tamper lists); every OTHER arming read must go through autonomy_on(). Comments
  # stripped first (a comment NAMING the rule is fine). Legacy keys must be GONE.
  _bad_new=""; _bad_old=""
  while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    _base=$(basename "$_f")
    case "$_base" in
      _lib.sh|l3-push-gate.sh|l3-loop-guard.py) _newok=1 ;; *) _newok=0 ;; esac
    _active=$(sed -E 's/#.*$//' "$_f" 2>/dev/null)
    if [ "$_newok" = "0" ] && printf '%s\n' "$_active" | grep -qE 'KBG_AUTONOMY([^_A-Z]|$)'; then
      _bad_new="$_bad_new $_f"
    fi
    if printf '%s\n' "$_active" | grep -qE 'KBG_AUTONOMY_L3|KBG_L3_REVIEW_DONE'; then
      _bad_old="$_bad_old $_f"
    fi
  done < <(find "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/scripts" -type f \( -name '*.sh' -o -name '*.py' \) 2>/dev/null)
  [ -z "$_bad_new" ] || crit "audit #48c: raw KBG_AUTONOMY literal outside autonomy_on() in:$_bad_new — every arming read must route through autonomy_on() (design §5 F1/#48c)"
  [ -z "$_bad_old" ] || crit "audit #48c: leftover legacy autonomy key(s) in active code:$_bad_old — the single-key collapse must be complete (KBG_AUTONOMY_L3/KBG_L3_REVIEW_DONE → KBG_AUTONOMY/KBG_REVIEW_DONE)"
  # 48d: F4 installer fail-safe present (design §5 F4 + §12 guards 1+2). The guard
  # MUST anchor REPO_ROOT to the mutated tree (git toplevel of CWD) + affirmatively
  # assert repo-identity (.claude-plugin/plugin.json name=='kbg') — without it a
  # flag-armed installer is stopped only by the silent, brittle cache-has-no-.git
  # path, which evaporates the moment a delivery path makes the cache a git repo.
  # Static grep over the guard source; a removed/renamed anchor → CRIT.
  _GUARD48="$CLAUDE_DIR/scripts/l3-loop-guard.py"
  if [ -f "$_GUARD48" ]; then
    _gsrc=$(cat "$_GUARD48" 2>/dev/null)
    _f4bad=""
    printf '%s\n' "$_gsrc" | grep -qF '_assert_repo_root' || _f4bad="$_f4bad _assert_repo_root(def)"
    printf '%s\n' "$_gsrc" | grep -qF 'show-toplevel'      || _f4bad="$_f4bad git-toplevel"
    printf '%s\n' "$_gsrc" | grep -qF '.claude-plugin'     || _f4bad="$_f4bad plugin.json-sentinel"
    printf '%s\n' "$_gsrc" | grep -qF '!= "kbg"'           || _f4bad="$_f4bad name==kbg-check"
    [ -z "$_f4bad" ] || crit "audit #48d: l3-loop-guard.py F4 anchoring incomplete (missing:$_f4bad) — the installer fail-safe (REPO_ROOT anchor + repo-identity) must stay in place (design §5 F4)"
  fi
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
