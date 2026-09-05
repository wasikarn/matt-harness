#!/usr/bin/env bash
# 71. Codex review-gate state (the paired codex@openai-codex plugin's
# Stop-time LLM-judgment review gate must stay off by design -- CONTEXT.md's
# "review gate" entry, ADR-0001, docs/reference/codex-integration-map.md).
# WARN only -- this reads third-party, operator-machine state, not a rule this
# repo can enforce; fail-open to INFO on anything missing or unparseable, same
# as every other check here that reads outside its own tree.
_codex_data="${MH_CODEX_DATA_DIR:-$HOME/.claude/plugins/data/codex-openai-codex}"
if [ ! -d "$_codex_data" ]; then
  info "codex@openai-codex not installed (no $_codex_data) -- Codex pairing inactive"
else
  _codex_state_file=$(codex_state_path "$REPO_ROOT" 2>/dev/null || true)
  if [ -z "$_codex_state_file" ]; then
    info "codex@openai-codex installed; no sha256 tool (shasum/sha256sum) found -- cannot locate review-gate state"
  elif [ ! -f "$_codex_state_file" ]; then
    info "codex@openai-codex installed; review-gate state not found for this repo (never toggled) -- off"
  elif ! command -v python3 >/dev/null 2>&1; then
    info "codex@openai-codex installed; python3 not found -- cannot read review-gate state ($_codex_state_file)"
  else
    _codex_gate=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print("on" if d.get("config", {}).get("stopReviewGate") else "off")
except Exception:
    print("unknown")
' "$_codex_state_file" 2>/dev/null)
    case "$_codex_gate" in
      on) warn "codex@openai-codex review gate is ON for this repo ($_codex_state_file) -- an LLM-judgment Stop hook that can block a session end; mh's doctrine keeps this off (CONTEXT.md, ADR-0001). Run /codex:setup --disable-review-gate" ;;
      off) info "codex@openai-codex review gate is off for this repo" ;;
      *) info "codex@openai-codex review-gate state file found but unparseable ($_codex_state_file) -- treating as off" ;;
    esac
    unset _codex_gate
  fi
  unset _codex_state_file
fi
unset _codex_data
