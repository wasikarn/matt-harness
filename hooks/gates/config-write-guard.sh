#!/usr/bin/env bash
# Gate: ask before CREATING a brand-new Claude Code settings file
# (.claude/settings.json, .claude/settings.local.json -- covers both the
# user-level ~/.claude/ and any project-level .claude/ dir, since both share
# that same basename shape).
#
# Why the asymmetry: an edit lands on a file a human has already reviewed at
# least once; a brand-new file introduces a whole unreviewed behavior surface
# with no prior review anchor. Same create-vs-modify split as the pre-commit
# new-file LOC gate (git-hooks/pre-commit), applied here at tool-call time via
# a plain existence check instead of at commit time via `git diff --diff-filter=A`.
#
# ASK, not DENY: creating a new settings file is reversible (it can be
# deleted), so this isn't the "irrecoverable set" DENY gates exist for.
#
# EDITING an existing settings file is also checked, but only for three
# security-relevant keys: `hooks` (a matt-side skill like
# git-guardrails-claude-code can instruct the model to merge a new entry into
# hooks.PreToolUse -- installing a hook this repo's own tamper-resistance
# gates never review), `enabledPlugins` (can flip this plugin's own enabled
# flag off), and `env` -- Claude Code injects a settings file's `env` block
# into the session AND the subprocesses it spawns (docs/reference/env-vars.md),
# so an edit to that key could silently set an escape-hatch var this repo's
# own gates already honor (MH_ALLOW_MAIN_EDIT, MH_ALLOW_DIRECT_ATLASSIAN_MCP)
# without ever touching hooks/enabledPlugins directly. Every other key --
# statusLine, permissions, theme, etc. -- stays frictionless, matching this
# gate's own "an already-reviewed file needs no friction" philosophy for the
# ordinary case. The edit is reconstructed from the on-disk content plus the
# tool's own Write/Edit payload and compared key-by-key against the original;
# a change to any of the three keys, or content on either side that cannot be
# parsed as JSON, asks. Fail-toward-ask on the unverifiable case -- but this
# scope is narrower than verifier-protect.sh's own invariant: verifier-protect
# also asks on a malformed top-level payload it cannot parse at all, while
# this gate's outer exception handler still allows on that specific failure
# (an intentionally unchanged, pre-existing safety net for genuinely
# unexpected errors, not touched by this security check -- see the try/except
# structure below). The "same invariant" claim below is scoped to the
# hooks/enabledPlugins/env comparison itself, not this file's entire error
# handling.
#
# Scope: Write and Edit tools only. MultiEdit is out of scope, same
# pre-existing gap verifier-protect.sh already has for that tool. A
# Bash-mediated create or edit (`echo '{}' > .claude/settings.json`, `jq`/
# `sed -i` rewriting an existing one) bypasses this gate entirely -- accepted
# gap, not closed here, same accepted-and-documented shape as
# credential-guard.sh's own Bash-mediated-reads gap (#96). Porting
# verifier-protect.sh's Bash-argv parser to cover this file too is out of
# proportion to this fix.
#
# #98, deferred-idea backlog filed from spec #75's migration (2026-08-24).
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found -- config-write-guard cannot run; allowing" >&2
  exit 0
fi

# Corrupted/partial plugin install (deep-audit follow-up to #146, same fix
# shape as verifier-protect.sh/merge-door.sh): this gate's embedded python
# does `from _hook_output import emit_ask`, resolved from this gate's
# sibling lib/ dir (passed as argv[1] below). A missing lib module raises
# ModuleNotFoundError -> exit 1 (confirmed live), a nonzero non-2 exit that
# hooks/dispatch-pretooluse.py's own dispatch contract treats as
# non-blocking -- the gated settings write proceeds regardless, i.e. this
# tamper-resistance gate fails OPEN. Emit the same ask-JSON shape
# emit_ask() would produce instead of letting the traceback exit nonzero.
_lib="$(dirname "$0")/lib"
if [ ! -r "$_lib/_hook_output.py" ]; then
  printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "config-write-guard: required module lib/_hook_output.py is missing or unreadable -- failing safe, approve manually or investigate the plugin install."}}'
  exit 0
fi

python3 -c '
import sys, json, os
sys.path.insert(0, sys.argv[1])
from _hook_output import emit_ask

SECURITY_KEYS = ("hooks", "enabledPlugins", "env")

def reconstruct(tool, ti, old_raw):
    # Returns the new file content the tool call would produce, or None if
    # it cannot be determined from the payload alone.
    if tool == "Write":
        content = ti.get("content")
        return content if isinstance(content, str) else None
    if tool == "Edit":
        old_s = ti.get("old_string")
        new_s = ti.get("new_string")
        if not isinstance(old_s, str) or not isinstance(new_s, str):
            return None
        if old_s not in old_raw:
            return None
        count = -1 if ti.get("replace_all") else 1
        return old_raw.replace(old_s, new_s, count)
    return None

def security_keys(raw):
    # Returns the SECURITY_KEYS tuple of values, or None if raw cannot be
    # parsed as a JSON object -- "unverifiable," handled the same as a
    # genuine mismatch by the caller.
    try:
        parsed = json.loads(raw)
    except Exception:
        return None
    if not isinstance(parsed, dict):
        return None
    return tuple(parsed.get(k) for k in SECURITY_KEYS)

try:
    d = json.load(sys.stdin)
    tool = d.get("tool_name")
    ti = d.get("tool_input")
    if not isinstance(ti, dict):
        sys.exit(0)
    fp = ti.get("file_path")
    if not isinstance(fp, str) or not fp:
        sys.exit(0)

    # normpath only -- deliberately NOT realpath. This gate classifies
    # "is something already sitting at this path," and realpath would
    # resolve a dangling symlink to its (missing) target and misreport it
    # as absent. lexists() below is the actual existence check.
    path = os.path.normpath(os.path.expanduser(fp))
    parent, base = os.path.split(path)
    # Case-INsensitive basename/parent match, same reasoning as
    # _protected_paths.py/verifier-protect.sh: macOS/APFS is case-insensitive
    # but case-preserving, so ".claude/SETTINGS.JSON" resolves to the same
    # on-disk file as ".claude/settings.json" while a case-sensitive string
    # compare treats them as unrelated -- a one-character-case Write/Edit
    # would otherwise skip this gate entirely on this exact filesystem.
    # Lowercasing only widens the match (more asks, never fewer), so this is
    # safe on case-sensitive filesystems too.
    if base.lower() not in ("settings.json", "settings.local.json"):
        sys.exit(0)
    if os.path.basename(parent).lower() != ".claude":
        sys.exit(0)

    if not os.path.lexists(path):
        emit_ask(
            "config-write-guard: creating a new Claude Code settings file (" + path +
            ") -- a fresh, unreviewed behavior surface. Confirm this is intentional."
        )
        sys.exit(0)

    # MODIFY of an existing file (or a symlink already there). Frictionless
    # unless the edit touches a SECURITY_KEYS entry -- read the current
    # content and compare against what the edit would produce.
    try:
        with open(path, "r") as f:
            old_raw = f.read()
    except (OSError, UnicodeDecodeError):
        # OSError: dangling symlink or unreadable. UnicodeDecodeError: the
        # on-disk file has a non-UTF-8 byte somewhere -- NOT an OSError
        # subclass, so this needs its own arm. Without it, a single stray
        # invalid byte anywhere in the file (from prior corruption or an
        # unrelated Bash-mediated write) would fall through to the outer
        # bare except and silently allow every subsequent Write/Edit against
        # this file, including one that rewrites a SECURITY_KEYS entry --
        # defeating the exact path this gate exists to cover. Cannot verify
        # either way, so treat it the same as unreadable.
        old_raw = None

    old_keys = security_keys(old_raw) if old_raw is not None else None
    new_raw = reconstruct(tool, ti, old_raw) if old_raw is not None else None
    new_keys = security_keys(new_raw) if new_raw is not None else None

    if old_keys is not None and new_keys is not None and old_keys == new_keys:
        sys.exit(0)  # verified unchanged -- no friction

    emit_ask(
        "config-write-guard: this edit to " + path +
        " could not be verified to leave hooks/enabledPlugins/env unchanged " +
        "(unreadable original, unparseable content, or a real change to " +
        "one of those keys). Confirm this is intentional."
    )
except Exception:
    sys.exit(0)
' "$_lib"
