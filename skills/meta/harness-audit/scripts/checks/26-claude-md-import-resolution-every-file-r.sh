#!/usr/bin/env bash
# 26. CLAUDE.md @-import resolution — every `@file` reference must resolve to a
# real file relative to the importing CLAUDE.md. Claude Code inlines these on
# load; a dangling ref (after an imported doctrine file is renamed or moved)
# silently loads nothing, dropping that doctrine from every session with no
# error. The check covers any CLAUDE.md in the repo. CRIT: the break is
# unambiguous and silently strips core behavior.
#
# Per code.claude.com/docs/en/memory.md (confirmed 2026-08-20), an @-import
# can appear anywhere in the file, not just at line start — the doc's own
# example is mid-sentence ("See @README for project overview and @package.json
# for dependencies"). The prior version of this check matched line-start only
# and would have missed a real dangling mid-line import. It also never
# excluded code spans, so a backtick-wrapped plugin id like `mh@kobig` would
# match `@kobig`, resolve to no file, and fire a false CRIT the moment a real
# import existed to trigger the scan at all — confirmed no false CRIT fires
# today only because this repo has zero real imports (verified 2026-08-20).
# Fenced code blocks are stripped first, then inline `backtick` spans, then a
# match requires @ to be preceded by whitespace or start-of-line (real imports
# per the doc are always in that position; a mid-word @ like `mh@kobig`
# never is — a second, independent guard against the same false-positive
# class even if a future edit un-backticks a plugin id).
#
# Process substitution (not a pipe) keeps crit() in the current shell so the
# count folds into the exit code.
while IFS= read -r cmd; do
  [ -f "$cmd" ] || continue
  cmd_dir=$(dirname "$cmd")
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    # Expand leading tilde (~/) to $HOME before the case so tilde doesn't
    # silently fail to expand inside shell-quoted patterns. The case itself
    # has to quote the pattern (shell syntax requirement); disable SC2088
    # because the post-statement will already have $HOME substituted in.
    # shellcheck disable=SC2088
    case "$ref" in
      "~/"*) ref="$HOME/${ref#"~/"}" ;;
    esac
    # shellcheck disable=SC2088  # literal-pattern requirement; tilde already expanded above
    case "$ref" in
      /*)    target="$ref" ;;
      *)     target="$cmd_dir/$ref" ;;
    esac
    if [ ! -e "$target" ]; then
      crit "CLAUDE.md '${cmd#$REPO_ROOT/}' import '@$ref' resolves to no file"
    fi
  done < <(
    awk '/^```/{f=!f; next} !f' "$cmd" 2>/dev/null \
      | sed -E 's/`[^`]*`//g' \
      | grep -oE '(^|[[:space:]])@[^[:space:]`]+' \
      | sed -E 's/^[[:space:]]*@//' \
      | sort -u \
      || true
  )
done < <(find "$REPO_ROOT" -name 'CLAUDE.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null || true)

