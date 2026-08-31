#!/usr/bin/env bash
# 67. composer-not-creator sourcing check (GH #119) — root CLAUDE.md's
# "Composer-not-creator doctrine" says check mattpocock-skills before writing
# a new skill/agent from scratch, but nothing enforced that computationally.
# It was already violated for real once: `code-implementer`/`/implement`
# collided with matt's own `implement` skill (CLAUDE.md:96-115), caught by
# the user, not by any check. WARN when a skill/agent's own name or
# description looks like it might duplicate one of the mattpocock-skills
# ledger entries, unless the file carries the literal marker
# "composer-not-creator: checked, genuinely new" (case-insensitive,
# anywhere in the file) recording that the author actually checked.
#
# Sourcing: pure read of the checked-in ledger table
# (docs/reference/mattpocock-integration-map.md — same table-row awk as
# check 50 sub-check C), NOT the live mattpocock-skills plugin cache. The
# ledger ships in this repo and is present regardless of whether the
# companion plugin is installed on this machine, so the portability
# directive ("assume a clean machine, no operator MCPs/CLIs/clones" —
# docs/reference/) is satisfied by construction: there is no cache-presence
# branch to skip because nothing here reads the cache. Missing ledger ->
# INFO skip (this check has nothing to compare against, not a gate failure).
#
# Heuristic (deliberately narrow — an early word-boundary description sweep
# against all 25 ledger names, measured live against this repo's real fleet
# 2026-09-01, hit 8 false positives: single-word matt names used as ordinary
# English verbs ("triage open PR review comments") and descriptions that
# already carry a correct `mattpocock-skills:<name>` cross-reference. A
# looser hyphen-OR-space description match added 6 more false positives, all
# generic English phrases like "code review" with no hyphen. Both classes
# were dropped rather than special-cased away — see the two signals below):
#   1. NAME: candidate's own `name:` frontmatter contains a ledger name as a
#      plain substring, no word boundary — this is what would have caught
#      "code-implementer" against "implement" ("implement" is a substring of
#      "implementer", not word-bounded, so a boundary-anchored match would
#      have missed the one real incident this check exists to prevent).
#      Checked against all 25 ledger names.
#   2. DESCRIPTION: candidate's `description:` frontmatter contains a
#      HYPHENATED (2+ word) ledger name as a literal hyphenated substring,
#      after stripping any `mattpocock-skills:<name>` tokens first (a
#      correct cross-reference, not a collision). No space-form fallback —
#      that's what produced the "code review"-as-English-phrase noise.
#      Single-word ledger names (triage, research, implement, teach,
#      handoff, wizard, prototype, tdd, wayfinder, grilling) are skipped for
#      description matching; signal 1 already covers "named after it" with
#      far better precision than a common-English-word description sweep.
# Both signals are WARN, not CRIT — per this repo's operating model, a false
# collision is always recoverable (add the marker or rename), so this
# advises rather than blocks (docs/reference/operating-model.md).
MARKER="composer-not-creator: checked, genuinely new"
_ledger="$CLAUDE_DIR/docs/reference/mattpocock-integration-map.md"
if [ ! -f "$_ledger" ]; then
  info "mattpocock integration ledger missing (docs/reference/mattpocock-integration-map.md) — composer-not-creator sourcing check skipped, nothing to compare against"
else
  _matt_names=()
  while IFS= read -r _n; do
    [ -n "$_n" ] && _matt_names+=("$_n")
  done < <(awk -F'|' '/^\|/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' "$_ledger" 2>/dev/null | grep -vE '^-+$|^$|^skill$')

  if [ "${#_matt_names[@]}" -eq 0 ]; then
    warn "composer-not-creator check: ledger table parsed 0 skill names from docs/reference/mattpocock-integration-map.md — table format drifted; this check is blind until the parser is updated (fail-closed)"
  else
    for _f in "$CLAUDE_DIR"/agents/*.md \
              "$CLAUDE_DIR"/skills/[!_]*/SKILL.md "$CLAUDE_DIR"/skills/[!_]*/[!_]*/SKILL.md; do
      [ -f "$_f" ] || continue
      grep -qiF "$MARKER" "$_f" 2>/dev/null && continue
      _rel=${_f#"$CLAUDE_DIR"/}
      _cname=$(fm_get "$_f" "name" | tr '[:upper:]' '[:lower:]')
      _cdesc=$(fm_get "$_f" "description" | tr '[:upper:]' '[:lower:]')
      _cdesc_stripped=$(printf '%s' "$_cdesc" | sed -E 's/mattpocock-skills:[a-zA-Z0-9\/_-]+//g')
      for _mn in "${_matt_names[@]}"; do
        _mn_lc=$(printf '%s' "$_mn" | tr '[:upper:]' '[:lower:]')
        if [ -n "$_cname" ]; then
          case "$_cname" in
            *"$_mn_lc"*)
              warn "'$_rel': name '$_cname' looks like it might duplicate mattpocock-skills:$_mn_lc — check that skill first (root CLAUDE.md's composer-not-creator doctrine), then add the literal marker \"$MARKER\" to this file if it's genuinely new"
              continue 2
              ;;
          esac
        fi
        case "$_mn_lc" in
          *-*)
            if [ -n "$_cdesc_stripped" ]; then
              case "$_cdesc_stripped" in
                *"$_mn_lc"*)
                  warn "'$_rel': description mentions '$_mn_lc' (a mattpocock-skills name) with no mattpocock-skills:$_mn_lc cross-reference — check that skill first (root CLAUDE.md's composer-not-creator doctrine), then add the literal marker \"$MARKER\" to this file if it's genuinely new"
                  continue 2
                  ;;
              esac
            fi
            ;;
        esac
      done
    done
  fi
fi
unset MARKER _ledger _matt_names _n _f _rel _cname _cdesc _cdesc_stripped _mn _mn_lc
