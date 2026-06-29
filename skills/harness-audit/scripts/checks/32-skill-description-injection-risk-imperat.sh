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

