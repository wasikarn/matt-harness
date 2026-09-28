#!/usr/bin/env bash
# eval-changed.sh [--run] [<git-ref>] — maps changed agents/skills files to their
# `claude plugin eval` tag and prints (or, with --run, executes) the case for each.
# Local-only: CI wiring was declined (no ANTHROPIC_API_KEY secret on this repo, and
# each eval run is a paid API call) — this is the developer-triggered substitute for
# "continuous evals on agent-config change" from the AI-Native SDLC playbook audit
# (docs/research/ai-native-sdlc-playbook-audit-2026-08-28.md, Round 4 gap list).
# No <ref>: diffs the working tree (staged + unstaged) against HEAD. With <ref>: diffs
# <ref>...HEAD instead, e.g. `eval-changed.sh develop` before a push.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

run=0
ref=""
for arg in "$@"; do
  case "$arg" in
    --run) run=1 ;;
    *) ref="$arg" ;;
  esac
done

if [ -n "$ref" ]; then
  changed=$(git diff --name-only "$ref"...HEAD)
else
  changed=$(git diff --name-only HEAD; git diff --name-only --cached)
fi

tags=$(printf '%s\n' "$changed" \
  | /usr/bin/grep -E '^(agents/[^/]+\.md|skills/[^/]+/[^/]+/)' \
  | sed -E 's#^agents/([^/]+)\.md#\1#; s#^skills/[^/]+/([^/]+)/.*#\1#' \
  | sort -u)

if [ -z "$tags" ]; then
  echo "eval-changed: no changed agent/skill files, nothing to eval." >&2
  exit 0
fi

while IFS= read -r tag; do
  # Union every allowed_tools list declared across this tag's own eval cases
  # (prompt.md frontmatter) instead of hardcoding a duplicate per-tag list.
  allow=$(python3 -c "
import re, sys, pathlib
tools = set()
for p in pathlib.Path('evals').glob('${tag}*/prompt.md'):
    text = p.read_text()
    fm = text.split('---')[1] if text.startswith('---') else ''
    if not re.search(r'^tags:\s*\[' + re.escape('$tag') + r'\b', fm, re.M):
        continue
    m = re.search(r'^allowed_tools:\s*\[([^\]]*)\]', fm, re.M)
    if m:
        tools.update(t.strip() for t in m.group(1).split(','))
print(','.join(sorted(tools)))
")
  cmd=(claude plugin eval . --scaffold --tag "$tag" --runs 1 --no-publish)
  [ -n "$allow" ] && cmd+=(--allow-tools "$allow")
  if [ "$run" -eq 1 ]; then
    echo "== $tag =="
    "${cmd[@]}"
  else
    printf '%q ' "${cmd[@]}"; echo
  fi
done <<< "$tags"
