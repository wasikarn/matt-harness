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

# ── md2adf: task lists emit VALID ADF (localId + inline content) ──────────
# Jira rejects taskItems missing localId or wrapped in a paragraph with
# INVALID_INPUT (verified TP-636). Guards the G1 fix — revert it (drop localId or
# re-wrap content in a paragraph) and tl_check prints INVALID, failing both lines.
echo "── md2adf task list -> valid ADF (G1) ──"
tl_check="$(printf '## C\n- [ ] a\n- [x] b\n' | python3 "$ACLI/scripts/md2adf.py" - | python3 -c '
import json, sys
d = json.load(sys.stdin)
def walk(n):
    if isinstance(n, dict):
        if n.get("type") == "taskList": yield n
        for v in n.values(): yield from walk(v)
    elif isinstance(n, list):
        for x in n: yield from walk(x)
tl = next(walk(d), None)
ok = bool(tl) and "localId" in tl.get("attrs", {}) \
     and all("localId" in it.get("attrs", {}) for it in tl["content"]) \
     and all(it["content"][0]["type"] == "text" for it in tl["content"])
print("VALID" if ok else "INVALID")
')"
check_contains "md2adf task list: localId + inline content" "$tl_check" "VALID"
check_absent   "md2adf task list: not paragraph-wrapped"    "$tl_check" "INVALID"

# ── acli-ls.py: list-or-dict unwrap + nested-field guards (no acli needed) ─
# A naive `f['parent']['key']` / `f['assignee']['displayName']` crashes on the
# unassigned/no-parent row → no output. That these rows render proves the guards.
echo "── acli-ls.py table (unwrap + guards) ──"
ls_dict='{"issues":[
  {"key":"TP-2","fields":{"issuetype":{"name":"Story"},"status":{"name":"Done"},"parent":{"key":"TP-1"},"assignee":{"displayName":"Aoy"},"summary":"child"}},
  {"key":"TP-3","fields":{"issuetype":{"name":"Task"},"status":{"name":"To Do"},"parent":null,"assignee":null,"summary":"orphan"}}
]}'
ls_out="$(printf '%s' "$ls_dict" | python3 "$ACLI/scripts/acli-ls.py")"
check_contains "ls: dict-shape unwraps (issues key)" "$ls_out" "TP-2"
check_contains "ls: parent shown as p:KEY"           "$ls_out" "p:TP-1"
check_contains "ls: null parent/assignee guarded"    "$ls_out" "orphan"
check_contains "ls: bare-list shape unwraps"         "$(printf '[{"key":"TP-9","fields":{"issuetype":{"name":"Bug"},"status":{"name":"Open"},"summary":"x"}}]' | python3 "$ACLI/scripts/acli-ls.py")" "TP-9"
check_contains "ls: empty set message"               "$(printf '{"issues":[]}' | python3 "$ACLI/scripts/acli-ls.py")" "(no matches)"

# ── acli-set-desc.sh --dry-run: renders body, sends nothing (no acli needed) ─
echo "── acli-set-desc.sh --dry-run ──"
sd_md="$(mktemp -t sd.XXXXXX.md)"
printf '## Goal\nทำให้เสร็จ\n\n- [ ] task one\n' > "$sd_md"
sd_out="$(bash "$ACLI/scripts/acli-set-desc.sh" TP-1 "$sd_md" --dry-run)"
rm -f "$sd_md"
check_contains "set-desc: REPLACES banner" "$sd_out" "REPLACES the ENTIRE description"
check_contains "set-desc: renders body"    "$sd_out" "Goal"
check_contains "set-desc: nothing sent"    "$sd_out" "nothing sent"

# ── summary ──────────────────────────────────────────────────────────────
echo ""
echo "Passed: $pass   Failed: $fail"
if [ "$fail" -ne 0 ]; then
    printf '%s\n' "${fail_msgs[@]}"
    exit 1
fi
echo "All acli script guards pass."
