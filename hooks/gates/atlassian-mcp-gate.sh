#!/usr/bin/env bash
# Gate: block a direct Atlassian/Jira/Confluence MCP call (any mcp__*atlassian*/
# mcp__*rovo* tool -- both a locally-configured/plugin MCP server, e.g.
# mcp__plugin_atlassian_atlassian__*, and a claude.ai-hosted connector, e.g.
# mcp__claude_ai_Atlassian_Rovo__*) before a jira-acli:* skill has loaded this
# session. Escalates ~/.claude/CLAUDE.md's "route through jira-acli first"
# doctrine + the advisory/jira-route-nudge.sh UserPromptSubmit reminder from
# prose to a computational PreToolUse gate -- both proved insufficient in
# practice (2026-07-15: still routing straight to the Atlassian MCP).
#
# This is a COLD-START guard, not a per-call router: once jira-acli:acli /
# jira-acli:jira-content / jira-acli:confluence-content loads once in a
# session, every later Atlassian MCP call that session is allowed. That is
# intentional, not a loophole -- confluence-content's page create/update has
# no acli equivalent and genuinely needs the MCP as its primary path, and
# acli:acli's own documented "When acli can't" fallback list (parent
# reassignment, accountId-assign, fixVersions, issue-type metadata, page
# create/update, cross-project move) legitimately calls this same MCP. A
# gate that blocked every call unconditionally would break the sanctioned
# skills' own main flow, not just the bypass this exists to catch.
#
# Wired under TWO PreToolUse matchers in hooks.json against this one script
# (mirrors verifier-protect.sh's dual "Write|Edit|MultiEdit" + "Bash" wiring):
#   - matcher "Skill"    -> marks the session engaged when tool_input.skill
#                           starts with "jira-acli:". Never blocks Skill itself.
#   - matcher "mcp__.*"  -> the actual gate. Broad matcher on purpose (no
#                           existing hooks.json matcher mixes literal
#                           alternation with regex metacharacters -- keeping
#                           the matcher dumb and doing the real
#                           atlassian/rovo discrimination here is the proven
#                           shape, see db-write-gate.sh's single-prefix
#                           matcher for the same reasoning applied narrower).
#
# ponytail: bash-greps the raw JSON before paying the python3 cold-start
# (~20ms) on every mcp__* call in every project loading this plugin --
# "mcp__.*" also matches mongodb/code-review-graph/qmd/playwright/figma/
# any SQL-server MCP, none of which this gate cares about. The grep is a permissive
# pre-filter (a superset of real matches, re-checked properly in python
# against tool_name alone) -- it can only skip work that would exit 0 anyway,
# never suppress a real block.
#
# Session marker: ~/.local/share/kbg/jira-acli-sessions/<session_id>, plain
# touch (no expiry -- a session ends the tmp namespace with it; leftover
# 0-byte files are harmless). Assumes subagents share the parent session_id
# in the hook payload, so a marker set by the orchestrator is visible to a
# dispatched subagent's own Atlassian MCP calls without it having to reload
# the skill. NOT independently confirmed against the official hooks doc --
# code.claude.com/docs/en/hooks documents session_id generically ("Current
# session identifier") and confirms agent_id/agent_type distinguish a
# subagent's hook events, but does not explicitly state whether session_id
# itself is identical to the parent's. Re-verify empirically (dispatch a
# subagent, diff its hook payload's session_id against the parent's) before
# relying on this for anything higher-stakes than the current cold-start nudge.
#
# Escape hatch: KBG_ALLOW_DIRECT_ATLASSIAN_MCP=1 (precedent:
# worktree-guard.py's KBG_ALLOW_MAIN_EDIT=1) -- cheap insurance if the
# marker ever misfires; not documented in docs/reference/env-vars.md, same
# as KBG_ALLOW_MAIN_EDIT isn't -- both are one-off manual overrides, not
# operator-tunable knobs.
set -uo pipefail

INPUT=$(cat)

if ! grep -qiE '"tool_name": ?"Skill"|atlassian|rovo' <<< "$INPUT"; then
  exit 0
fi

# Portability (#93): this gate enforces "route through jira-acli first" — a
# doctrine that only applies when the jira-acli plugin is actually installed.
# On a machine without it, blocking would prescribe skills the user cannot
# load, so the correct behavior is a clean allow. Glob probes any publisher
# (cache/<publisher>/jira-acli) rather than hardcoding one; with no match the
# glob stays literal and the -d test fails, so this is bash-3.2-safe.
_jira_acli_found=0
for _d in "${HOME:-}"/.claude/plugins/cache/*/jira-acli; do
  if [ -d "$_d" ]; then _jira_acli_found=1; break; fi
done
[ "$_jira_acli_found" -eq 1 ] || exit 0

# Portability guard (#93): announced fail-open when python3 is missing;
# doctrine-bootstrap.sh names the missing dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[kbg:gate] python3 not found — atlassian-routing gate cannot run; allowing (install python3 to restore jira-acli routing)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, os, re, sys

STATE_DIR = os.path.expanduser("~/.local/share/kbg/jira-acli-sessions")

def marker_path(session_id):
    safe = re.sub(r"[^a-zA-Z0-9_-]", "_", session_id or "nosession")
    return os.path.join(STATE_DIR, safe)

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)  # cannot parse -- fail open, matches worktree-guard.py convention

if os.environ.get("KBG_ALLOW_DIRECT_ATLASSIAN_MCP") == "1":
    sys.exit(0)

tool = d.get("tool_name", "") or ""
ti = d.get("tool_input", {}) or {}
session = d.get("session_id", "") or ""
mpath = marker_path(session)

if tool == "Skill":
    skill = str(ti.get("skill", "") or "")
    if re.match(r"^jira-acli:", skill):
        os.makedirs(STATE_DIR, exist_ok=True)
        open(mpath, "a").close()  # touch
    sys.exit(0)  # Skill invocation itself is never blocked by this gate

if not tool.startswith("mcp__"):
    sys.exit(0)

if not re.search(r"atlassian|rovo", tool, re.IGNORECASE):
    sys.exit(0)  # not an Atlassian/Rovo MCP tool -- out of scope

if os.path.exists(mpath):
    sys.exit(0)  # jira-acli already engaged this session -- allow

print(
    "[kbg:gate] BLOCKED: direct Atlassian/Jira MCP call (" + tool + ") before "
    "jira-acli loaded this session. Load jira-acli:acli (mechanical/query/bulk "
    "ops), jira-acli:jira-content (Bug/Story/Task/Epic/Sub-task templates), or "
    "jira-acli:confluence-content (Spec/PRD pages) first -- they own the "
    "ADF/template standard, and this exact MCP call is already their own "
    "documented fallback path when acli genuinely cannot. One-off override: "
    "KBG_ALLOW_DIRECT_ATLASSIAN_MCP=1",
    file=sys.stderr,
)
sys.exit(2)
' <<< "$INPUT"
exit $?
