# 45. Reviewer read-only invariant (maker≠checker). An agent whose NAME marks it a
# reviewer/analyzer (reviewer|analyzer|analyst|hunter|critic|judge) must NOT grant
# Write or Edit: a verifier that can mutate what it reviews defeats the fresh-context
# independence maker≠checker depends on. Load-bearing at L3 (CLAUDE.md §The operating model (was L3 bounded autonomy, retired)) — these agents
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
    crit "agent '$name' is a reviewer but grants '$bad' — read-only invariant (maker≠checker) broken; reviewers must not mutate what they review (CLAUDE.md §The operating model (was L3 bounded autonomy, retired) §L3 evolution)"
  fi
done

