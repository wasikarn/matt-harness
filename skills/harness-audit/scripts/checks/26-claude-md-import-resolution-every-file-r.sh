#!/usr/bin/env bash
# 26. CLAUDE.md @-import resolution — every `@file` reference at line start must
# resolve to a real file relative to the importing CLAUDE.md. Claude Code inlines
# these on load; a dangling ref (after an imported doctrine file is renamed or
# moved) silently loads nothing, dropping that doctrine from every session with
# no error. Today only claude/CLAUDE.md imports (@METHODOLOGY.md, @RTK.md), but
# the check covers any CLAUDE.md in the repo. CRIT: the break is unambiguous and
# silently strips core behavior. Process substitution (not a pipe) keeps crit()
# in the current shell so the count folds into the exit code.
while IFS= read -r cmd; do
  [ -f "$cmd" ] || continue
  cmd_dir=$(dirname "$cmd")
  while IFS= read -r line; do
    ref="${line#@}"
    ref="${ref%%[[:space:]]*}"
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
  done < <(grep -E '^@[^[:space:]]' "$cmd" 2>/dev/null || true)
done < <(find "$REPO_ROOT" -name 'CLAUDE.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null || true)

