#!/usr/bin/env bash
# Gate: block a raw `gh pr merge` on a non-clean review-pr state.
#
# Closes the bypass that let the tathep compliance-audit-round-2 session
# (6e7c3bed) merge PR #2768 at review round 12: the cross-pass convergence
# gate's enforcement point lived only inside ship-merge (disable-model-
# invocation — the model cannot invoke it), so the model merged via raw
# `gh pr merge`, which had NO gate. The verifier was never connected to the
# one-way door actually used (found 2026-08-13).
#
# Reads the PreToolUse JSON payload from stdin. Exit 0 = allow; exit 2 =
# block (prints "[kbg:gate] BLOCKED: <reason>" to stderr). Mirrors the
# deny protocol in irrecoverable.sh.
#
# Decision: resolve the review-pr state file
# (${REVIEW_PR_STATE_DIR:-~/.claude/state}/review-pr-<N>.json keyed by PR
# number, else review-last.json unkeyed). If no state file exists -> allow
# (unreviewed merge is ship-merge's concern, not this gate's). If the state
# shows clean == true -> allow (clean wins, matching ship-merge line 49).
# If clean != true (unresolved Critical / incomplete rehunt / dispatch
# failure) -> block, naming round + convergence_state, redirecting to
# /kbg:ship-merge. Fail-closed on an unreadable file or a missing/non-bool
# `clean` field: a merge we cannot confirm clean is not allowed.
set -uo pipefail

# --- Fast path: skip python entirely on the common (non-merge) path. ---
# This gate runs on every Bash command in every repo with the plugin; a
# python3 cold-start per command is the latency cost the PreToolUse-parallel
# lesson says to kill. Read stdin once, then decide.
_input="$(cat)"
# JSON encodes in-string newlines/tabs as the two-char \n / \t; collapse
# those and squeeze all whitespace so a multi-line `gh pr\n  merge` still
# matches. Glob for `gh` ... `pr merge`: gh may be bare `gh` or /path/gh,
# and global flags (gh --repo X pr merge) may sit between gh and pr. A rare
# prose false positive (the `gh` inside `weigh` next to a bare `pr merge`)
# just spawns python, which tokenizes with shlex and allows -- quoted prose
# stays one token, so it never splits into bare `pr` + `merge`.
_norm="$(printf '%s' "$_input" | sed 's/\\[nt]/ /g' | tr -s '[:space:]' ' ')"
case "$_norm" in
  *gh*"pr merge"*) : ;;  # candidate -- python decides
  *) exit 0 ;;           # no merge possible -- allow, no cold-start
esac

# --- Slow path: a candidate merge command. Tokenize precisely in python. ---
# shellcheck disable=SC2016  # single quotes are intentional: Python code
printf '%s' "$_input" | python3 -c '
import json, os, shlex, sys

try:
    d = json.load(sys.stdin)
except Exception:
    # Malformed payload is irrecoverable.sh'\''s concern (it fails closed
    # there); this gate only adds a merge check, so fail-SAFE allow.
    sys.exit(0)

if not isinstance(d, dict) or not isinstance(d.get("tool_input"), dict):
    sys.exit(0)

cmd = d["tool_input"].get("command", "")

# Find a REAL `gh ... pr merge [<num>]` subcommand. Tolerate global flags
# between `gh` and `pr` (gh --repo owner/repo pr merge 42). shlex keeps
# quoted prose as one token, so a prose mention of "gh pr merge" never
# splits into bare pr+merge tokens. Normalize newlines to spaces BEFORE
# tokenizing (matching the bash fast-path'\''s sed): a real `gh pr\n  merge`
# (JSON serializes the newline as \n) is ONE command split across lines --
# per-line tokenization would miss it (`pr` is the last token on line 1,
# `merge` the first on line 2), so tokenize the whole normalized command.
# ponytail: joining lines lets gh_seen carry across what were separate
# commands (e.g. `gh auth status` then `pr merge`), a contrived false
# positive that only fires on a non-clean review state -- safe direction.
# Ceiling: split on shell separators (;, &&, ||) and reset gh_seen per
# command if a real cross-command false positive appears.
cmd = cmd.replace("\r", " ").replace("\n", " ")
try:
    tokens = shlex.split(cmd, posix=True)
except ValueError:
    tokens = []
pr_num = None
has_merge = False
gh_seen = False
for j, t in enumerate(tokens):
    if t == "gh" or t.endswith("/gh"):
        gh_seen = True
        continue
    if gh_seen and t == "pr" and j + 1 < len(tokens) and tokens[j + 1] == "merge":
        has_merge = True
        for a in tokens[j + 2:]:
            if not a.startswith("-"):
                pr_num = a
                break
        break

if not has_merge:
    sys.exit(0)

# --- Resolve the review-pr state file. ---
state_dir = os.environ.get("REVIEW_PR_STATE_DIR") or os.path.expanduser("~/.claude/state")
state_file = None
if pr_num:
    keyed = os.path.join(state_dir, "review-pr-{}.json".format(pr_num))
    if os.path.isfile(keyed):
        state_file = keyed
if state_file is None:
    unkeyed = os.path.join(state_dir, "review-last.json")
    if os.path.isfile(unkeyed):
        state_file = unkeyed

if state_file is None:
    # No review state on disk -- unreviewed merge, not this gate'\''s concern.
    sys.exit(0)

# --- Parse and decide. ---
try:
    with open(state_file) as f:
        s = json.load(f)
except Exception:
    print("[kbg:gate] BLOCKED: review state file exists but is unreadable"
          " (" + state_file + "); cannot confirm a clean review. "
          "Use /kbg:ship-merge to merge -- it reads this state by score.",
          file=sys.stderr)
    sys.exit(2)

if not isinstance(s, dict):
    # Valid JSON but not an object (a list/string/number from a corrupted or
    # hand-edited state file) -- the fields cannot be read. Fail closed.
    print("[kbg:gate] BLOCKED: review state (" + state_file + ") is valid JSON "
          "but not an object; cannot confirm a clean review. "
          "Use /kbg:ship-merge to merge.", file=sys.stderr)
    sys.exit(2)

clean = s.get("clean")
if not isinstance(clean, bool):
    # Missing or wrong-type clean on a merge attempt -> fail closed.
    print("[kbg:gate] BLOCKED: review state (" + state_file + ") has no "
          "boolean '\''clean'\'' field; cannot confirm a clean review. "
          "Use /kbg:ship-merge to merge.", file=sys.stderr)
    sys.exit(2)

if clean is True:
    # Clean wins regardless of force_human (matches ship-merge line 49):
    # 0 Criticals, rehunt clean, no dispatch failures -> merge freely.
    # BUT a clean review with failing/pending CI must not auto-merge via raw
    # gh (Slice 1): the ship-merge scored gate checks CI on the human-only
    # path (wt 25); this closes the same gap on the raw-gh auto path. The
    # merge one-way door now gates on BOTH clean AND CI-green.
    import subprocess
    ci_args = ["gh", "pr", "checks"]
    if pr_num:
        ci_args.append(str(pr_num))
    ci_args += ["--json", "name,state,conclusion"]
    try:
        ci_r = subprocess.run(ci_args, capture_output=True, text=True, timeout=20)
    except Exception:
        # gh timed out / not found / unlaunchable -> unknown, NOT N/A. Fail
        # closed: a merge we cannot confirm CI-green is not allowed.
        print("[kbg:gate] BLOCKED: clean review but CI status unreadable"
              " (gh pr checks errored/timed out); cannot confirm CI green. "
              "Use /kbg:ship-merge to merge -- it scores CI.", file=sys.stderr)
        sys.exit(2)
    ci_checks = None
    if ci_r.stdout.strip():
        try:
            ci_checks = json.loads(ci_r.stdout)
        except Exception:
            ci_checks = None
    if ci_checks is None:
        # Unparseable or empty stdout. Distinguish no-CI from a gh error:
        # empty + returncode 0 => repo has no CI configured => N/A => allow.
        # empty/unparseable + returncode != 0 => gh errored (auth, no PR,
        # rate limit) => unknown, NOT N/A => fail closed. (A real check
        # failure still outputs JSON with --json and exits 0; a nonzero exit
        # here means gh itself failed, not that a check failed.)
        if ci_r.returncode == 0:
            sys.exit(0)
        print("[kbg:gate] BLOCKED: clean review but CI status unreadable"
              " (gh pr checks exit={}); cannot confirm CI green. "
              "Use /kbg:ship-merge to merge -- it scores CI.".format(
                  ci_r.returncode), file=sys.stderr)
        sys.exit(2)
    # ponytail: treat ALL checks (cannot filter on required: true -- gh pr
    # checks --json has no required field). SUCCESS/NEUTRAL/SKIPPED = green;
    # anything else (FAILURE, TIMED_OUT, CANCELLED, ACTION_REQUIRED, or
    # null=pending) = not green -> deny. Pending -> deny is correct: do not
    # merge while CI is running; ship-merge scores pending CI low too.
    # Ceiling: filter on required: true once gh exposes it reliably, so a
    # failing non-required check does not block. Stricter-now is the safe
    # direction (deny -> redirect to the ship-merge required-check gate).
    if isinstance(ci_checks, list) and ci_checks:
        bad = [c.get("name", "?") for c in ci_checks
               if not isinstance(c, dict)
               or c.get("conclusion") not in ("SUCCESS", "NEUTRAL", "SKIPPED")]
        if bad:
            print("[kbg:gate] BLOCKED: clean review but CI not green"
                  " -- {} not SUCCESS. Use /kbg:ship-merge to merge"
                  " (it scores CI at weight 25).".format(", ".join(bad[:5])),
                  file=sys.stderr)
            sys.exit(2)
    # empty list => no CI configured for this repo => N/A (not zeroed) =>
    # allow. CI is not this repo merge model (direct-push-to-develop); the
    # check only bites when CI IS configured and not green.
    sys.exit(0)

# ponytail: block on `clean` only, not on force_human / round-ceiling. The
# round-ceiling enforcement stays in ship-merge (the human-only path); this
# gate blocks the one condition that is the actual failure -- a non-clean
# review reaching the one-way door. Ceiling: if a non-clean review at round
# >= ceiling should be blocked even from raw gh regardless of clean, widen
# to `clean is not True or force_human is True`. Not needed today: clean is
# not True already covers every non-clean review, and a clean review at a
# high round is correctly mergeable.
rnd = s.get("round")
cstate = s.get("convergence_state")
reason = "raw `gh pr merge` on a non-clean review (clean=false)."
if isinstance(rnd, int):
    reason += " round={}.".format(rnd)
if isinstance(cstate, str):
    reason += " convergence_state={}.".format(cstate)
reason += (" /kbg:ship-merge is the merge path -- it reads this convergence "
           "state and blocks non-clean reviews by score. Do not raw-merge.")
print("[kbg:gate] BLOCKED: " + reason, file=sys.stderr)
sys.exit(2)
'
rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  echo "[kbg:gate] internal error (rc=$rc) — failing closed" >&2
  exit 2
fi
exit "$rc"