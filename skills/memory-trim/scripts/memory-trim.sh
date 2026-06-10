#!/usr/bin/env bash
# memory-trim.sh — apply the A3 trim rubric to the active memory store.
#
# Subcommands:
#   plan   — print the action plan (dry-run only)
#   apply  — apply after confirm; --yes skips the prompt
#   status — show before/after MEMORY.md size and lint finding count
#
# Reads the memory dir from the same auto-derivation memory-lint uses
# (cwd → ~/.claude/projects/<enc>/memory). Override with MEMORY_DIR env.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/../../memory-lint/scripts/memory-lint.py"

# Auto-derive memory dir (mirrors memory-lint.py:memory_dir)
derive_memory_dir() {
    if [ -n "${MEMORY_DIR:-}" ]; then
        echo "$MEMORY_DIR"
        return
    fi
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -z "$root" ]; then
        echo "ERROR: not in a git repo and MEMORY_DIR is unset" >&2
        exit 1
    fi
    local enc="${root//\//-}"
    echo "$HOME/.claude/projects/${enc}/memory"
}

MD_DIR="$(derive_memory_dir)"
MD_FILE="$MD_DIR/MEMORY.md"

cmd="${1:-plan}"
shift || true

case "$cmd" in
    plan)
        echo "memory-trim plan: $MD_DIR"
        echo
        python3 "$LINT" "$MD_DIR" --auto-archive --dry-run
        ;;
    apply)
        yes_flag=""
        if [ "${1:-}" = "--yes" ]; then
            yes_flag="--yes"
        fi
        # Capture size before
        if [ -f "$MD_FILE" ]; then
            before_bytes=$(wc -c < "$MD_FILE" | tr -d ' ')
        else
            before_bytes=0
        fi
        before_findings=$(python3 "$LINT" "$MD_DIR" 2>/dev/null | awk '/^Exit: /{print $2; exit}' || true)
        if [ -z "$before_findings" ]; then before_findings="?"; fi
        echo "memory-trim apply: $MD_DIR"
        echo "  before: ${before_bytes}B, ${before_findings} lint findings"
        echo
        # Run with --dry-run to show plan, then ask confirm unless --yes
        if [ -z "$yes_flag" ]; then
            python3 "$LINT" "$MD_DIR" --auto-archive --dry-run
            echo
            read -rp "Apply? [y/N] " ans
            case "$ans" in
                y|Y|yes|YES) ;;
                *) echo "Aborted."; exit 1 ;;
            esac
        fi
        # Apply
        echo
        echo "Applying..."
        python3 "$LINT" "$MD_DIR" --auto-archive --yes 2>&1 | tail -20
        # Capture size after + re-lint
        if [ -f "$MD_FILE" ]; then
            after_bytes=$(wc -c < "$MD_FILE" | tr -d ' ')
        else
            after_bytes=0
        fi
        after_findings=$(python3 "$LINT" "$MD_DIR" 2>/dev/null | awk '/^Exit: /{print $2; exit}' || true)
        if [ -z "$after_findings" ]; then after_findings="?"; fi
        delta=$((after_bytes - before_bytes))
        echo
        echo "═══════════════════════════════════════"
        echo "  before: ${before_bytes}B, ${before_findings} findings"
        echo "  after:  ${after_bytes}B, ${after_findings} findings"
        echo "  delta:  ${delta}B ($(awk "BEGIN{printf \"%.1f\", $delta/1024}")KB)"
        echo "═══════════════════════════════════════"
        ;;
    status)
        if [ ! -f "$MD_FILE" ]; then
            echo "ERROR: MEMORY.md not found at $MD_FILE" >&2
            exit 1
        fi
        bytes=$(wc -c < "$MD_FILE" | tr -d ' ')
        lines=$(wc -l < "$MD_FILE" | tr -d ' ')
        pct=$(awk "BEGIN{printf \"%d\", ($bytes/25600)*100}")
        findings=$(python3 "$LINT" "$MD_DIR" 2>/dev/null | awk '/^Exit: /{print $2; exit}' || true)
        if [ -z "$findings" ]; then findings="?"; fi
        echo "memory-trim status: $MD_DIR"
        echo "  MEMORY.md: ${bytes}B / ${lines}L (${pct}% of 25KB cap)"
        echo "  lint findings: ${findings}"
        ;;
    *)
        echo "usage: $0 {plan|apply [--yes]|status}" >&2
        exit 1
        ;;
esac
