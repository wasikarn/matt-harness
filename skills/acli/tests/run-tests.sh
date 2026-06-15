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

# ── md2adf: heading levels 1–6 (H4-H6 used in patterns-thai.md + plan files) ──
# Earlier the heading regex matched only `#{1,3}` so `####`/`#####`/`######` fell
# through to paragraphs (empty content). This was the latent bug behind TP-641's
# missing-level-4 headings in comments. Revert the regex back to `#{1,3}` and the
# check prints "MISSING" instead of "OK", failing both lines.
echo "── md2adf heading levels 1–6 (G2) ──"
hl_check="$(printf '# H1\n## H2\n### H3\n#### H4\n##### H5\n###### H6\n' | python3 "$ACLI/scripts/md2adf.py" - | python3 -c '
import json, sys
d = json.load(sys.stdin)
def walk(n):
    if isinstance(n, dict):
        if n.get("type") == "heading": yield n
        for v in n.values(): yield from walk(v)
    elif isinstance(n, list):
        for x in n: yield from walk(x)
headings = list(walk(d))
levels = sorted({h.get("attrs", {}).get("level") for h in headings})
ok = levels == [1, 2, 3, 4, 5, 6] and len(headings) == 6
print("OK" if ok else f"MISSING (got {levels})")
')"
check_contains "md2adf h4-h6: all 6 levels parsed" "$hl_check" "OK"
check_absent   "md2adf h4-h6: no missing levels"    "$hl_check" "MISSING"

# ── md2adf: underscore italic respects word boundaries (G3) ─────────────
# Bug seen on TP-641 v2 comment #1 block 12: `price_per_car` was matched as
# `price` + `per` (italic) + `car` because the old `_(italic)_` rule had no
# lookarounds. CommonMark rule: `_` only opens/closes italic when both
# neighbours are non-word characters. Revert the new lookarounds and the
# `em_around_per` node appears (italic span inside an identifier).
echo "── md2adf underscore italic: word-boundary guard (G3) ──"
g3_check="$(printf 'a price_per_car b and _em_ and snake_case_id\n' | python3 "$ACLI/scripts/md2adf.py" - | python3 -c '
import json, sys
d = json.load(sys.stdin)
def walk(n):
    if isinstance(n, dict):
        if n.get("type") == "text" and n.get("text"): yield n
        for v in n.values(): yield from walk(v)
    elif isinstance(n, list):
        for x in n: yield from walk(x)
nodes = list(walk(d))
# Expect: price_per_car and snake_case_id stay LITERAL (no em mark),
#         and the standalone _em_ becomes italic.
def em_around_per():  # bug signature: `per` node has marks=[em]
    for n in nodes:
        if n.get("text") == "per" and any(m.get("type") == "em" for m in n.get("marks", [])):
            return True
    return False
def em_on_em():
    for n in nodes:
        if n.get("text") == "em" and any(m.get("type") == "em" for m in n.get("marks", [])):
            return True
    return False
ok = (not em_around_per()) and em_on_em()
print("OK" if ok else f"BUG (per_italic={em_around_per()}, em_italic={em_on_em()})")
')"
check_contains "md2adf underscore: price_per_car stays literal" "$g3_check" "OK"
check_absent   "md2adf underscore: no italic on identifier's per" "$g3_check" "BUG"

# ── md2adf: bold does not swallow backtick-wrapped code (G4) ──────────────
# Bug seen on TP-641 v2 comment #2 block 27: `**`UpdateAiCampaignPlanBillboardsUseCase.ts:34-36`**`
# rendered as a single strong span containing backticks, instead of bold-mark + code-mark.
# Fix: bold pattern excludes backticks, AND code is matched first. Revert either and the
# code span disappears / gets folded into the strong mark.
echo "── md2adf bold: does not swallow code (G4) ──"
g4_check="$(printf 'see **label** `code` here and **`code`** splittable\n' | python3 "$ACLI/scripts/md2adf.py" - | python3 -c '
import json, sys
d = json.load(sys.stdin)
def walk(n):
    if isinstance(n, dict):
        if n.get("type") == "text" and n.get("text"): yield n
        for v in n.values(): yield from walk(v)
    elif isinstance(n, list):
        for x in n: yield from walk(x)
nodes = list(walk(d))
marks = [(n.get("text"), [m.get("type") for m in n.get("marks", [])]) for n in nodes]
# Expect: a code-marked node for `code` (text == "code" with marks==[code]),
#         and a strong-marked node for `label` (text == "label" with marks==[strong]).
def has_code(): return any(t == "code" and ms == ["code"] for t, ms in marks)
def has_label_strong(): return any(t == "label" and ms == ["strong"] for t, ms in marks)
ok = has_code() and has_label_strong()
print("OK" if ok else f"BUG {marks}")
')"
check_contains "md2adf bold: code span survives nested marks" "$g4_check" "OK"
check_absent   "md2adf bold: no bold-swallowed-code"          "$g4_check" "BUG"

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
