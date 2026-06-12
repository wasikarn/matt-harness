#!/usr/bin/env bash
# run-tests.sh — deterministic guards for the acli skill's helper scripts.
#
# Convention mirrors skills/memory-lint/tests + skills/harness-audit/tests:
# each skill owns its tests; fixtures live in-repo (the shipped examples/*.json),
# not /tmp, for reproducibility.
#
# Exit 0 = all pass, 1 = at least one failure.
#
# Guard history:
#   adf2md create-payload preview (S2, 2026-06-12) — a flat acli create-payload
#   (--from-json shape: top-level summary/projectKey/type/description, NO `fields`
#   wrapper) used to render a blank `# ? ·` header and silently drop project/type/
#   priority. That made the SKILL.md "preview before create" step untrustworthy:
#   it hid exactly the metadata most likely to be wrong. render_create_card() fixed
#   it. These assertions revert-and-fail if that regresses (test-honesty Rule 6).

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ACLI="$(cd "$HERE/.." && pwd)"
ADF2MD="python3 $ACLI/scripts/adf2md.py"

pass=0
fail=0
fail_msgs=()

check_contains() {  # <label> <output> <needle>
    if printf '%s' "$2" | grep -qF -- "$3"; then
        echo "  PASS: $1"
        pass=$((pass + 1))
    else
        echo "  FAIL: $1"
        fail_msgs+=("$1 — expected to find: $3")
        fail=$((fail + 1))
    fi
}

check_absent() {  # <label> <output> <needle>
    if printf '%s' "$2" | grep -qF -- "$3"; then
        echo "  FAIL: $1"
        fail_msgs+=("$1 — should NOT contain: $3")
        fail=$((fail + 1))
    else
        echo "  PASS: $1"
        pass=$((pass + 1))
    fi
}

# ── adf2md: create-payload preview surfaces metadata ─────────────────────
# Asserts on the HEADER marker `# (new) <type>` and the `**Project:**` meta line,
# NOT a bare type substring: story-template's body has a "User Story" heading, so
# grepping for "Story" alone would pass even with the blank-header bug. The header
# marker + project line only appear when render_create_card runs.
echo "── adf2md create-payload preview (story) ──"
story_out="$($ADF2MD "$ACLI/examples/story-template.json")"
check_contains "story: header shows type"      "$story_out" "# (new) Story"
check_contains "story: project key surfaced"   "$story_out" "**Project:** TP"
check_absent   "story: no blank header"        "$story_out" "# ? ·"

echo "── adf2md create-payload preview (bug) ──"
bug_out="$($ADF2MD "$ACLI/examples/bug-template.json")"
check_contains "bug: header shows type"        "$bug_out" "# (new) Bug"
check_contains "bug: project key surfaced"     "$bug_out" "**Project:** TP"
check_absent   "bug: no blank header"          "$bug_out" "# ? ·"

echo "── adf2md create-payload preview (sub-task: parent surfaced) ──"
sub_out="$($ADF2MD "$ACLI/examples/subtask-template.json")"
check_contains "subtask: header shows type"    "$sub_out" "# (new) Sub-task"
check_contains "subtask: parent surfaced"      "$sub_out" "**Parent:**"

# ── adf2md: a real view payload (has `fields`) still renders as a card ────
# Guards that the create-payload branch didn't swallow the view-payload path.
echo "── adf2md view payload still renders (regression guard) ──"
view_out="$(printf '%s' '{"key":"TP-1","fields":{"issuetype":{"name":"Bug"},"status":{"name":"Done"},"summary":"hi"}}' | $ADF2MD -)"
check_contains "view: key+type header"         "$view_out" "# TP-1 · Bug"

# ── summary ──────────────────────────────────────────────────────────────
echo ""
echo "Passed: $pass   Failed: $fail"
if [ "$fail" -ne 0 ]; then
    printf '%s\n' "${fail_msgs[@]}"
    exit 1
fi
echo "All acli script guards pass."
