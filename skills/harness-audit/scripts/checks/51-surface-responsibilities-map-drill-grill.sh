# 51. Surface Responsibilities map drift (grilling 2026-06-23, the
# responsibility-map deliverable). DOMAINS.md must carry a ## Surface
# Responsibilities section, and every Owner-context (col 3) + Couplings token
# (col 6) must be one of the five bounded contexts (plugin-surface, doctrine,
# audit-eval, infra, docs) — no third vocabulary may fork off the ## Contexts
# model. Catches the drift the panel flagged: a responsibility map that invents
# its own labels rots silently. Surface-on-disk existence is deliberately NOT
# checked here (plugin-cache vs repo portability); presence + label-vocabulary
# are the robust, high-value assertions.
if [ -f "$CLAUDE_DIR/DOMAINS.md" ]; then
  _dom51="$CLAUDE_DIR/DOMAINS.md"
  grep -q '^## Surface Responsibilities' "$_dom51" \
    || crit "audit #51: DOMAINS.md missing '## Surface Responsibilities' section — the per-surface ownership map is absent (the responsibility-map deliverable rotted away, grilling 2026-06-23)"
  _badctx51=$(awk '
    /^## Surface Responsibilities/ { secready=1; next }
    /^## / && secready { nextfile }
    secready && /^\| `/ {
      # skip the header row (Surface col has no backtick) and the |---| separator
      if (index($0,"| `") == 0) next
      n=split($0, f, "|")
      owner=f[3]; gsub(/^[ \t]+|[ \t]+$/, "", owner)
      coups=f[6]; gsub(/^[ \t]+|[ \t]+$/, "", coups)
      if (owner!="" && owner !~ /^(plugin-surface|doctrine|audit-eval|infra|docs)$/) print "owner:"owner
      m=split(coups, c, ",")
      for (i=1;i<=m;i++){ gsub(/^[ \t]+|[ \t]+$/,"",c[i]); if (c[i]!="" && c[i]!~ /^(plugin-surface|doctrine|audit-eval|infra|docs)$/) print "coupling:"c[i] }
    }
  ' "$_dom51")
  [ -z "$_badctx51" ] || crit "audit #51: DOMAINS.md Surface Responsibilities uses a context label outside the five bounded contexts:$(printf '%s' "$_badctx51" | tr '\n' ' ')— couple to {plugin-surface, doctrine, audit-eval, infra, docs} only; a third vocabulary forks the dispatch model"
fi

