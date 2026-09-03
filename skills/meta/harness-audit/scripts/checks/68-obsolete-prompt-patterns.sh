#!/usr/bin/env bash
# 68. Obsolete prompt patterns in agent/skill bodies. Ported from the
# CLI-bundled claude-api prompt-audit six-pattern list: (1) verification
# rituals, (2) emphasis boosters, (3) reasoning scaffolds, (4) stale
# examples, (5) contradictory rules, (6) dated thinking config. Patterns
# 4-5 are not greppable and stay a reading pass; the rest are below, plus
# the original three (dated prompt text / body steering language).
# One INFO per file per pattern, first matching line quoted:
#   - "step by step" / "step-by-step": the model reasons step-by-step
#     unprompted; the phrase is dead weight.
#   - pressure language ("You must", "It is critical/essential/imperative",
#     "this is critical"): state the rule plainly instead.
#   - uppercase steering (NEVER/ALWAYS/MUST) in the body: dial back.
#   - verification rituals (double-check, verify again, re-verify, check
#     your work): frontier models take it literally and duplicate work.
#   - thoroughness boosters (maximally thorough, be extremely thorough,
#     exhaustively): drives extra tool calls.
#   - reasoning scaffolds (scratchpad, <thinking>, thinking budget,
#     reasoning template): stacks on native reasoning.
#   - dated thinking config (budget_tokens, max_thinking, thinking:) —
#     FRONTMATTER scan, the only one; use effort: instead.
# Body only otherwise — frontmatter is skipped (check 29 owns description:).
# INFO, not WARN: fleet-wide hits measured <=9 on 2026-09-03, and some are
# load-bearing (a gate's deny message quoting its own rule). Lowercase
# `must` is deliberately excluded — ~27 files match it, pure noise.
# Scope: agents/*.md + skills SKILL.md (check 55's glob, `_`-prefixed
# excluded); harness-audit's own SKILL.md excluded (it documents these
# patterns and would self-trigger, mirroring check 34/47).
for _f in "$CLAUDE_DIR"/agents/*.md "$CLAUDE_DIR"/skills/[!_]*/SKILL.md "$CLAUDE_DIR"/skills/[!_]*/[!_]*/SKILL.md; do
  [ -f "$_f" ] || continue
  # Exclude by the skill's own dir name (check 34/47 shape), not a path glob:
  # check 57's `*/skills/harness-audit/*` glob also swallows every fixture
  # under tests/skills/harness-audit/, which is why it has no fixture test.
  [ "$(basename "$(dirname "$_f")")" = "harness-audit" ] && continue
  # Split frontmatter (between the first two `---` lines) from body. CRLF
  # files get `\r` stripped first so the `---` fence still matches. Body
  # drops fenced code blocks (``` ... ```) and inline `backtick` spans — a
  # quoted example of a pattern is not the pattern.
  _fm=$(awk '{sub(/\r$/,"")} NR==1 && $0=="---"{fm=1; next} fm && $0=="---"{exit} fm' "$_f")
  _body=$(awk '{sub(/\r$/,"")} NR==1 && $0=="---"{fm=1; next} fm && $0=="---"{fm=0; next} fm{next}
    /^[[:space:]]*```/{fence=!fence; next} fence{next} {gsub(/`[^`]*`/,"")} 1' "$_f")
  for _pat in \
    'step[- ]by[- ]step|model reasons step-by-step unprompted; delete' \
    '\b[Yy]ou must\b|\b[Ii]t is (critical|essential|imperative)\b|\bthis is critical\b|pressure language; state the rule plainly' \
    '\bNEVER\b|\bALWAYS\b|\bMUST\b|uppercase steering in body; dial back' \
    '\b(double|triple)[- ]check\b|\bverify (twice|again)\b|\bre-?verify\b|\bcheck your (own )?work\b|verification ritual; frontier models take it literally and duplicate work' \
    '\bmaximally thorough\b|\b(be|being) (extremely|very|as) thorough\b|\bas thorough as possible\b|\bexhaustively\b|thoroughness booster; drives extra tool calls' \
    '\bscratchpad\b|<thinking>|\bthinking budget\b|\breasoning template\b|reasoning scaffold; stacks on native reasoning' \
    'FM:budget_tokens|max_thinking|thinking:|dated thinking config; use effort: instead'; do
    _re="${_pat%|*}"; _msg="${_pat##*|}"
    case "$_re" in
      FM:*) _src="$_fm"; _re="${_re#FM:}" ;;
      *)    _src="$_body" ;;
    esac
    _hit=$(printf '%s\n' "$_src" | /usr/bin/grep -E -m1 "$_re" 2>/dev/null || true)
    [ -n "$_hit" ] || continue
    info "obsolete prompt pattern in ${_f#"$CLAUDE_DIR"/}: $_msg — first hit: ${_hit:0:100}"
  done
done
unset _f _fm _body _pat _re _msg _hit _src
