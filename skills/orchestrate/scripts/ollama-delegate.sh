#!/usr/bin/env bash
# ollama-delegate.sh — dispatch an F9-style prompt to an Ollama-hosted model
# via the verified read-only path (--permission-mode plan is hardcoded, never
# overridable by a caller flag — see orchestrate/SKILL.md's "necessary and
# verified" warning on that flag before touching this).
# Usage: bash ollama-delegate.sh [--model <name>] "<F9-style prompt>"
set -euo pipefail

model="minimax-m3:cloud"
if [ "${1:-}" = "--model" ]; then
  model="${2:?--model requires a value}"
  shift 2
fi
prompt="${1:?usage: ollama-delegate.sh [--model <name>] \"<F9-style prompt>\"}"

exec ollama launch claude --model "$model" --yes \
  -- -p "$prompt" --permission-mode plan
