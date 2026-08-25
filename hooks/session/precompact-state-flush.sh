#!/usr/bin/env bash
# PreCompact: flush a deterministic, non-LLM-summarized snapshot of the
# session's in-flight state (git status, HEAD, plugin manifest versions)
# to ~/.local/share/kbg/metrics/precompact-snapshots.jsonl before
# compaction runs (#92/T13). CLAUDE.md's own "Compact instructions"
# section already asks the compacting model to preserve exactly this class
# of fact in prose ("which files are staged/committed... the current
# plugin version state... any open plan-mode approval") — that's a prompt
# instruction, not a guarantee (this repo's own memory has repeated
# stale-count/stale-fact incidents from trusting a model's own summary).
# This hook is the computational backstop: the same class of fact, captured
# by a deterministic script instead of an LLM paraphrase, so a post-
# compaction turn can consult ground truth instead of trusting the summary
# alone.
#
# Pure flush, never a gate: this event supports permissionDecision:deny to
# block compaction, but blocking isn't this hook's job (advisory sensors
# journal, they don't gate — CLAUDE.md "Operating model"). No JSON on
# stdout, ever.
#
# ponytail: unbounded append, same precedent as the other metrics writers
# in this file's directory — rotate/trim manually if it grows large.
set -uo pipefail

payload=$(cat)

log_dir="$HOME/.local/share/kbg/metrics"
mkdir -p "$log_dir"

cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd="$PWD"

git_head=""
git_subject=""
git_status_json="[]"
if [ -d "$cwd" ] && command -v git >/dev/null 2>&1 && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_head=$(git -C "$cwd" rev-parse HEAD 2>/dev/null || true)
  git_subject=$(git -C "$cwd" log -1 --format=%s 2>/dev/null || true)
  git_status_json=$(git -C "$cwd" status --porcelain 2>/dev/null | jq -R -s -c 'split("\n") | map(select(length > 0))')
fi

plugin_version=""
marketplace_version=""
if [ -f "$cwd/.claude-plugin/plugin.json" ]; then
  plugin_version=$(jq -r '.version // empty' "$cwd/.claude-plugin/plugin.json" 2>/dev/null)
fi
if [ -f "$cwd/.claude-plugin/marketplace.json" ]; then
  marketplace_version=$(jq -r '.plugins[0].version // empty' "$cwd/.claude-plugin/marketplace.json" 2>/dev/null)
fi

jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson payload "$payload" \
  --arg cwd "$cwd" \
  --arg git_head "$git_head" \
  --arg git_subject "$git_subject" \
  --argjson git_status "$git_status_json" \
  --arg plugin_version "$plugin_version" \
  --arg marketplace_version "$marketplace_version" \
  '{
    ts: $ts,
    session_id: ($payload.session_id // "unknown"),
    compaction_reason: ($payload.compaction_reason // "unknown"),
    cwd: $cwd,
    git_head: (if $git_head == "" then null else $git_head end),
    git_last_commit_subject: (if $git_subject == "" then null else $git_subject end),
    git_status_porcelain: $git_status,
    plugin_version: (if $plugin_version == "" then null else $plugin_version end),
    marketplace_version: (if $marketplace_version == "" then null else $marketplace_version end)
  }' >>"$log_dir/precompact-snapshots.jsonl" 2>/dev/null

exit 0
