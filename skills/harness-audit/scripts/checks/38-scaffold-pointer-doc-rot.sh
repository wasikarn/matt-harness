#!/usr/bin/env bash
# 38. Scaffold-pointer doc-rot (a doctrine surface names a reasoning scaffold
# that does not resolve to a real `decide` mode, a real skill dir, or the
# documented external allowlist)
#
# The Rule-1 scaffold menu (clarify-first / probe / decide / strategize /
# critical-eval / doubt-driven) and the reference docs that bind it
# (decision-doctrine-map.md, judgment-ladder.md, reasoning-models.md) name
# concrete surfaces a reader is meant to follow. A surface cut (like the
# v0.6.0 242->87 consolidation) can fold scaffolds into `skills/decide`
# without updating every doc that still names the old surface — the exact
# defect class this guard fences (8 broken pointers found + fixed 2026-07-01:
# `skills/clarify-first`, `skills/critical-eval`, `kbg:decide (debate mode)`
# all cited a surface that never existed as a standalone skill or `decide`
# mode). WARN, not CRIT — advisory, matching check 37 and the operating
# model (sensors journal; CRIT is reserved for the irrecoverable/tamper set).
#
# Two resolution rules:
# (a) `kbg:decide <word> mode` / `kbg:decide (<word> mode)`: <word> must
#     appear as a `## Mode: <word>` heading in skills/decide/SKILL.md.
# (b) A bare `skills/<name>` / `kbg:<name>` reference to one of the three
#     hyphenated Rule-1 scaffold names that were the literal broken refs
#     found 2026-07-01 (clarify-first, critical-eval, doubt-driven) is
#     always doc-rot — none of the three has a skill dir, and doubt-driven
#     is deliberately an external fresh-context pattern that must never be
#     invoked as a `kbg:`/`skills:` surface (it needs a context the
#     invoking surface doesn't have). `probe`/`strategize`/`decide` are
#     excluded from rule (b): they're single common words that collide with
#     prose too easily to regex safely, and are already covered by rule (a)
#     in their real `kbg:decide <word> mode` form.
_SCAFFOLD_DOC_ROT_FILES=(
  "$CLAUDE_DIR"/docs/METHODOLOGY.md
  "$CLAUDE_DIR"/docs/reference/decision-doctrine-map.md
  "$CLAUDE_DIR"/docs/reference/judgment-ladder.md
  "$CLAUDE_DIR"/docs/reference/strategic-judgment.md
  "$CLAUDE_DIR"/docs/reference/reasoning-models.md
  "$CLAUDE_DIR"/skills/decide/SKILL.md
)
if [ -f "$CLAUDE_DIR/skills/decide/SKILL.md" ]; then
  _decide_modes=$(grep -hoE '^## Mode: [a-z]+' "$CLAUDE_DIR/skills/decide/SKILL.md" | sed 's/^## Mode: //' | sort -u)
else
  _decide_modes=""
fi
for _f in "${_SCAFFOLD_DOC_ROT_FILES[@]}"; do
  [ -f "$_f" ] || continue
  # Rule (a). Matches every real-world phrasing found in the doctrine layer:
  # `kbg:decide` clarify mode · `kbg:decide (strategize mode)` ·
  # skills/decide (probe mode) · `skills/decide` probe mode — the prefix is
  # followed by up to 4 non-letter chars (backtick/space/paren) then the
  # mode word then literal " mode".
  while IFS= read -r _word; do
    [ -z "$_word" ] && continue
    if ! printf '%s\n' "$_decide_modes" | grep -qx "$_word"; then
      warn "scaffold-pointer doc-rot in ${_f#"$CLAUDE_DIR"/}: cites '$_word mode' on kbg:decide/skills/decide but skills/decide/SKILL.md has no '## Mode: $_word' heading (doc-rot — pointer does not resolve)"
    fi
  done < <(grep -hoE '(kbg:decide|skills/decide)[^a-zA-Z]{0,4}[a-z]+ mode' "$_f" 2>/dev/null \
             | grep -oE '[a-z]+ mode$' | sed 's/ mode$//' | sort -u)
  # Rule (b). A bare surface-style reference to a hyphenated scaffold name
  # that was never real is always the defect — no resolution check needed.
  while IFS= read -r _bare; do
    [ -z "$_bare" ] && continue
    warn "scaffold-pointer doc-rot in ${_f#"$CLAUDE_DIR"/}: cites '$_bare' as an invokable surface, but it has no skill dir and is not a kbg:decide mode (doc-rot — pointer does not resolve)"
  done < <(grep -hoE '(skills/|kbg:)(clarify-first|critical-eval|doubt-driven)' "$_f" 2>/dev/null | sort -u)
done
unset _f _word _bare _decide_modes _SCAFFOLD_DOC_ROT_FILES
