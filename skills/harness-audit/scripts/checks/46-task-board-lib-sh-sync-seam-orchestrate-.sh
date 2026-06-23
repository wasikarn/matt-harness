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

