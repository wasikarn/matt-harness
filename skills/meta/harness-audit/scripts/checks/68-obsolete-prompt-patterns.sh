#!/usr/bin/env bash
# 68. Obsolete prompt patterns in agent/skill bodies. Ported from the
# CLI-bundled claude-api prompt-audit pattern table (group 1: dated prompt
# text that current models no longer need; group 3: steering language that
# belongs in a description's trigger phrasing, not shouted in the body).
# Three patterns, one INFO per file per pattern, first matching line quoted:
#   - "step by step" / "step-by-step": the model reasons step-by-step
#     unprompted; the phrase is dead weight.
#   - pressure language ("You must", "It is critical/essential/imperative",
#     "this is critical"): state the rule plainly instead.
#   - uppercase steering (NEVER/ALWAYS/MUST) in the body: dial back.
# Body only — frontmatter is skipped (check 29 owns description: scanning).
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
  # Strip frontmatter: drop everything up to and including the second `---`.
  _body=$(awk 'NR==1 && $0=="---"{fm=1; next} fm && $0=="---"{fm=0; next} !fm' "$_f")
  for _pat in \
    'step[- ]by[- ]step|model reasons step-by-step unprompted; delete' \
    '\b[Yy]ou must\b|\b[Ii]t is (critical|essential|imperative)\b|\bthis is critical\b|pressure language; state the rule plainly' \
    '\bNEVER\b|\bALWAYS\b|\bMUST\b|uppercase steering in body; dial back'; do
    _re="${_pat%|*}"; _msg="${_pat##*|}"
    _hit=$(printf '%s\n' "$_body" | /usr/bin/grep -E -m1 "$_re" 2>/dev/null || true)
    [ -n "$_hit" ] || continue
    info "obsolete prompt pattern in ${_f#"$CLAUDE_DIR"/}: $_msg — first hit: ${_hit:0:100}"
  done
done
unset _f _body _pat _re _msg _hit
