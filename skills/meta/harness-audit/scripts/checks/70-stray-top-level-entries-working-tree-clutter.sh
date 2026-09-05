#!/usr/bin/env bash
# 70. Stray top-level entries (working-tree clutter Claude Code globs every session)
# Gitignored eval workspaces, graphify caches, and scratch dirs never reach git, so
# nothing in the gauntlet ever saw them — but every Glob/Grep in a session did
# (2026-09-06: 22 `*-workspace/` dirs, ~500 graphify cache files, .scratch/ sitting
# in the tree three months after the rebuild rule said "delete everything else").
# WARN only; the operator trashes or extends the allowlist. Plugin-mode (flat repo)
# only — the dotfiles layout nests the fleet under claude/ and has its own top level.
if [ "$CLAUDE_DIR" = "$REPO_ROOT" ]; then
  _allow=" .git .github .claude .claude-plugin .gitattributes .gitignore .DS_Store CHANGELOG.md CLAUDE.md LICENSE README.md agents docs git-hooks hooks pyrightconfig.json scripts skills tests "
  for _e in "$REPO_ROOT"/* "$REPO_ROOT"/.*; do
    [ -e "$_e" ] || continue
    _b=$(basename "$_e")
    case "$_b" in .|..) continue ;; esac
    case "$_allow" in *" $_b "*) continue ;; esac
    warn "stray top-level entry '$_b' — not in the v1 keep list; Claude Code globs it every session. trash it, or add it to check 70's allowlist if it belongs"
  done
  unset _allow _e _b
fi
