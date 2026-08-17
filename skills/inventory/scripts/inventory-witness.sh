#!/usr/bin/env bash
# inventory-witness.sh — snapshot the current boundary map for drift detection.
# Generates a canonical BOUNDARY.md that can be committed and diff'd in CI.
# Usage: bash inventory-witness.sh [<output-path>]
set -euo pipefail

# shellcheck source=../../../scripts/_lib/err.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/_lib/err.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${1:-claude/BOUNDARY.md}"

echo "Generating boundary snapshot → $OUTPUT"
bash "$SCRIPT_DIR/inventory-boundary.sh" --repo-only > "$OUTPUT"

echo ""
echo "Done. Commit $OUTPUT to detect fleet drift:"
echo "  git add $OUTPUT && git commit -m 'chore(inventory): boundary snapshot $(date -u +%Y-%m-%d)'"
echo ""
echo "Verify in CI or locally:"
echo "  bash $SCRIPT_DIR/inventory-witness.sh /tmp/BOUNDARY_NEW.md && diff $OUTPUT /tmp/BOUNDARY_NEW.md"
