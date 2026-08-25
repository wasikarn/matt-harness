#!/usr/bin/env bash
# 5. Frontmatter completeness — skills
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/skills"/*/*/SKILL.md; do
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
  # Bucket check — path-derived (skills/<bucket>/<name>/SKILL.md), replacing
  # the old bucket: frontmatter check (2026-08-25 folder migration: path is
  # now the sole source of truth, frontmatter dropped to avoid a
  # two-places-that-can-drift risk). Two distinct severities: a flat skill
  # (skills/<name>/SKILL.md, no bucket dir) still loads fine via Claude
  # Code's default 1-level scan, just missing from BOUNDARY.md's grouping —
  # WARN, same severity the old frontmatter check used. A skill nested under
  # an unrecognized bucket name is covered by neither the default 1-level
  # scan nor plugin.json's explicit 6-bucket globs — genuinely undiscoverable
  # — CRIT.
  case "$f" in
    "$CLAUDE_DIR"/skills/*/*/SKILL.md)
      _bucket=$(basename "$(dirname "$(dirname "$f")")")
      case "$_bucket" in
        meta|review|workflow|patterns|agent-support|design) : ;;
        *) crit "skill '$name' is under unrecognized bucket dir '$_bucket' — plugin.json only globs meta/review/workflow/patterns/agent-support/design, so this skill is not discoverable" ;;
      esac
      ;;
    *) warn "skill '$name' is not under a bucket dir (flat skills/$name/SKILL.md) — degrades BOUNDARY.md grouping (still loads via the default scan)" ;;
  esac
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

