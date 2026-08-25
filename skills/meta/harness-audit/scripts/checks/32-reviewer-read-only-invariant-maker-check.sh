#!/usr/bin/env bash
# 32. Reviewer read-only invariant (maker≠checker). An agent whose NAME marks it a
# reviewer/analyzer (reviewer|analyzer|analyst|hunter|critic|judge|checker) must NOT grant
# Write or Edit: a verifier that can mutate what it reviews defeats the fresh-context
# independence maker≠checker depends on. Load-bearing doctrine: CLAUDE.md's Operating
# model paragraph, under its Architecture section (the L3 bounded-autonomy build it
# came from was retired; the maker≠checker rule survives there) — these agents
# run unattended inside the loop's Gate-2 review. The source frontmatter is read-only
# today (fix 5c06590); this is the regression guard against a future re-widening.
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  case "$name" in
    *reviewer*|*analyzer*|*analyst*|*hunter*|*critic*|*judge*|*checker*) ;;
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
    crit "agent '$name' is a reviewer but grants '$bad' — read-only invariant (maker≠checker) broken; reviewers must not mutate what they review (CLAUDE.md's Operating model paragraph, under its Architecture section)"
  fi
done

