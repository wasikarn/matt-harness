#!/usr/bin/env bash
# Gate: block a raw `gh pr merge` on a non-clean review-pr state.
#
# Defense-in-depth for the merge one-way door. Before this gate shipped
# (2026-08-13), the cross-pass convergence gate's ONLY enforcement point was
# `ship-merge`'s prose checklist (disable-model-invocation — the model cannot
# invoke it) plus a human confirming each step via AskUserQuestion. That's a
# real gap in principle: nothing at the tool-call level double-checked that
# an actual `gh pr merge` Bash invocation (which is how `ship-merge` itself
# executes a merge — there is no separate wrapped tool) corresponded to a
# clean state, so a procedural mistake in either the model's checklist
# reading or the human's confirmation had no independent backstop.
#
# Corrected 2026-08-14: this gate's original comment characterized the tathep
# session `6e7c3bed` (PR #2768) as having "ran a hand-rolled review (not
# review-pr), merged via raw gh pr merge, no gate" — a bypass narrative.
# Direct transcript verification disproves both claims: `review-pr` was
# invoked 16x with real reviewer-agent dispatch, and the merge followed
# `ship-merge`'s Phase 1/2 checklist with an explicit human AskUserQuestion
# confirmation on a genuinely clean, round-14 state (state file read at
# transcript line 12081 showed `clean:true, round:14`; confirmation at line
# 12128; merge at line 12131). The merge was clean and human-confirmed, not a
# bypass. This gate is still the right addition — it closes the
# defense-in-depth gap named above regardless of whether any specific past
# merge was clean — but its justification is architectural, not "this
# incident went wrong."
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
# Widened 2026-08-15 (issue #49): require "gh" and "merge" present ANYWHERE
# in the text, not the contiguous "pr merge" substring -- contiguous-only
# missed `gh pr $M 42` where `M=merge` sits elsewhere in the same command
# (the substring "merge" is real, just not adjacent to "pr"). Costs more
# python cold-starts on ordinary text mentioning both words; the python slow
# path's own indirection resolver (_deindirect below) does the precision
# work from here, same tradeoff this file already accepted for prose hits.
if [[ "$_norm" != *gh* || "$_norm" != *merge* ]]; then
  exit 0  # no merge possible -- allow, no cold-start
fi

# --- Slow path: a candidate merge command. Tokenize precisely in python. ---
# Resolve this gate's own directory from $0 rather than trusting
# CLAUDE_PLUGIN_ROOT alone -- hooks.json invokes this file as
# `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/convergence-merge-gate.sh"`, so $0
# is always the absolute path Claude Code actually launched, in every install
# mode (plugin cache, symlink farm, or a direct test invocation). An empty or
# stale CLAUDE_PLUGIN_ROOT env var would otherwise silently hard-block every
# clean, CI-green merge once the CODEOWNERS import fails below.
_gate_dir="$(cd -P "$(dirname "$0")" && pwd)"
# shellcheck disable=SC2016  # single quotes are intentional: Python code
printf '%s' "$_input" | python3 -c '
import glob, json, os, re, shlex, sys

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
def _deindirect(cmd, depth=0):
    # Best-effort: unwrap `<shell> -c "<nested>"` wrapping and resolve
    # simple same-command `VAR=value; ... $VAR ...` indirection, so the
    # token walk below sees what the shell would actually run instead of an
    # opaque quoted blob or an unexpanded variable name. Bounded recursion
    # against pathological nesting.
    # ponytail: heuristic, not a real shell interpreter. Single-quoted -c
    # bodies and single-quoted assignment values are not unwrapped here --
    # they fall through to the residual-indirection fail-closed check below
    # instead of being resolved. Command substitution ($(...), backticks)
    # and variables this command never itself assigns (env, export, a
    # parent shell) are never resolved either, by design -- same fail-closed
    # backstop. Ceiling: an interpreter -c/-e flag (python3 -c, perl -e)
    # running `gh pr merge` via a system call is not covered at all -- an
    # open-ended chase, out of scope for this fix.
    # github.com/wasikarn/kbg-harness/issues/49
    if depth > 5:
        return cmd

    resolved = re.sub(
        r"(?:^|[;&|]+\s*)(?:\S*/)?\w*sh\s+(?:-\S+\s+)*-[A-Za-z]*c\s+"
        r"\"((?:[^\"\\]|\\.)*)\"",
        lambda m: m.group(1),
        cmd,
    )

    assigns = {}
    for k, v in re.findall(
            r"(?<![-\w])([A-Za-z_]\w*)=(\"[^\"]*\"|[^\s;&|()]+)", resolved):
        if len(v) >= 2 and v[0] == "\"" and v[-1] == "\"":
            v = v[1:-1]
        assigns[k] = v
    # re.sub with a negative lookahead, not .replace(): a plain substring
    # replace of "$GH" also matches inside "$GHX" (GH is a literal prefix of
    # GHX), corrupting the longer name'\''s expansion. The lookahead requires
    # the char after the name to not continue an identifier. Lambda (not a
    # string) as the replacement so a literal `\` in v is never read as a
    # backreference. github.com/wasikarn/kbg-harness/issues/49
    for k, v in assigns.items():
        resolved = re.sub(r"\$\{" + re.escape(k) + r"\}",
                           lambda m, v=v: v, resolved)
        resolved = re.sub(r"\$" + re.escape(k) + r"(?![A-Za-z0-9_])",
                           lambda m, v=v: v, resolved)

    if resolved != cmd and depth < 5:
        return _deindirect(resolved, depth + 1)
    return resolved

def _any_at_risk_state(state_dir):
    # Scan every known review state file (keyed review-pr-*.json plus the
    # unkeyed review-last.json) and return True if ANY is non-clean or
    # unreadable. Shared by both places that can'\''t pin a merge command to
    # ONE specific PR: an ambiguous command (shell indirection this gate
    # can'\''t resolve) and a confirmed `gh pr merge` whose selector never
    # produces a numeric pr_num (bare invocation, --squash-only, a branch
    # name, a URL -- gh resolves all of those from the current branch, not
    # from the command text). Either way, a stale non-clean review for some
    # OTHER PR still blocks until cleaned up -- the safe direction, not a
    # bypass. github.com/wasikarn/kbg-harness/issues/49
    files = glob.glob(os.path.join(state_dir, "review-pr-*.json"))
    unkeyed = os.path.join(state_dir, "review-last.json")
    if os.path.isfile(unkeyed):
        files.append(unkeyed)
    for sf in files:
        try:
            with open(sf) as f:
                s = json.load(f)
        except Exception:
            return True
        if not (isinstance(s, dict) and s.get("clean") is True):
            return True
    return False

cmd = cmd.replace("\\\n", "")  # real backslash-newline continuation: bash
cmd = cmd.replace("\r", " ").replace("\n", " ")  # deletes both chars, joining
cmd = _deindirect(cmd)  # lines with whatever whitespace was already adjacent
# -- was `.replace("\n", " ")` alone, turning "\<NL>" into "\ " (backslash-
# space). shlex.shlex(posix=True) treats that as an ESCAPED space, folding
# it into the next token as a leading literal space ("merge" -> " merge"),
# breaking the adjacency check below. Confirmed a real `gh pr \`+newline+
# `merge 42` (bash'\''s own line-continuation syntax) rc=0-bypassed on the
# corrupted token. Order matters: the backslash-newline deletion MUST run
# before the general \n -> " " collapse below, or there'\''s no backslash left
# to match. github.com/wasikarn/kbg-harness/issues/49

# Command substitution / backtick / eval leave part of the command opaque to
# static tokenizing -- decide this BEFORE the has_merge walk, not after, and
# never trust that walk'\''s result when it'\''s true. Punctuation_chars mode
# below (needed to split on ; & |) also splits on ( and ), so a "gh" living
# INSIDE an unresolved $(...) leaks out as an ordinary top-level token once
# the parens become separators -- confirmed via `XPR=$(echo gh); $XPR pr
# merge 42`: the walk found a coincidental gh...pr merge sequence spanning
# across the substitution boundary and mis-classified it as a confirmed
# merge with a bogus pr_num, not the ambiguous case it actually is.
# github.com/wasikarn/kbg-harness/issues/49
has_opaque_indirection = "$(" in cmd or "`" in cmd or bool(re.search(r"\beval\b", cmd))

try:
    # shlex.split() alone never splits on ; & | -- "pull;gh" stays one glued
    # token and "gh" never surfaces for the has_merge walk below. punctuation_
    # chars=True makes shlex treat those as their own tokens (still quote-
    # aware), same fix the file'\''s own comment above already named as the
    # ceiling. Verified --repo owner/repo and /usr/local/bin/gh both still
    # tokenize intact under this mode. github.com/wasikarn/kbg-harness/issues/49
    _lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    _lex.whitespace_split = True
    tokens = list(_lex)
except ValueError:
    tokens = []
# Value-taking flags of the "gh pr merge" subcommand, separated-token form
# only -- glued forms like --repo=owner/repo or -Rowner/repo are already
# single tokens starting with "-" and are skipped below without needing this
# list. Verified against the cli/cli repository, file
# pkg/cmd/pr/merge/merge.go (StringVarP registrations), and
# cli.github.com/manual/gh_pr_merge, for gh 2.95.0. --repo has no
# subcommand-local registration there because it is the global -R/--repo
# flag, but it still takes a value the same way.
# github.com/wasikarn/kbg-harness/issues/51
_MERGE_VALUE_FLAGS = frozenset((
    "-R", "--repo",
    "-A", "--author-email",
    "-b", "--body",
    "-F", "--body-file",
    "-t", "--subject",
    "--match-head-commit",
))

state_dir = os.environ.get("REVIEW_PR_STATE_DIR") or os.path.expanduser("~/.claude/state")
pr_num = None
has_merge = False
if not has_opaque_indirection:
    gh_seen = False
    for j, t in enumerate(tokens):
        if t == "gh" or t.endswith("/gh"):
            gh_seen = True
            continue
        if gh_seen and t == "pr" and j + 1 < len(tokens) and tokens[j + 1] == "merge":
            has_merge = True
            skip_next = False
            for a in tokens[j + 2:]:
                if skip_next:
                    skip_next = False
                    continue
                if a in _MERGE_VALUE_FLAGS:
                    skip_next = True
                    continue
                if not a.startswith("-"):
                    pr_num = a
                    break
            break

if not has_merge:
    # Reached only because the (widened) bash fast-path found "gh" and
    # "merge" somewhere in the raw text. _deindirect() above already
    # resolved `<shell> -c "..."` wrapping and same-command `VAR=value; ...
    # $VAR ...` indirection into plain tokens -- a real merge hiding behind
    # either already surfaced in the walk above. What is left here is what
    # that heuristic could not resolve: command substitution, `eval`, or a
    # variable this command never itself assigns. Check TOKENS, not raw
    # substrings -- a bare `$VAR` sitting alone in an otherwise-innocuous
    # prose string is a real ambiguity; that same text embedded inside a
    # bigger quoted string (already inert prose to shlex) should not trip
    # this. github.com/wasikarn/kbg-harness/issues/49
    residual = has_opaque_indirection or bool(re.search(
        r"(?:^|[;&|]+\s*)(?:\S*/)?\w*sh\s+(?:-\S+\s+)*-[A-Za-z]*c\b", cmd
    )) or any(
        re.fullmatch(r"\$\{?[A-Za-z_]\w*\}?", t)
        for t in tokens
    )
    if residual:
        # has_merge is False here, so pr_num is never set -- we cannot know
        # WHICH review this ambiguous command might target. _any_at_risk_
        # state() checks every review-pr-*.json plus review-last.json,
        # since a prior version of this check looked only at the unkeyed
        # file and missed the realistic PR-by-number layout entirely:
        # write-review-state.sh writes ONLY review-pr-<N>.json for that
        # flow -- a full silent bypass for exactly the case `kbg:review-pr
        # <N>` produces. github.com/wasikarn/kbg-harness/issues/49
        if not _any_at_risk_state(state_dir):
            sys.exit(0)
        print("[kbg:gate] BLOCKED: command references gh/merge but also"
              " contains shell indirection (command substitution, eval, or"
              " a variable this command never assigns) this gate cannot"
              " statically resolve -- cannot confirm this is not a merge."
              " Run `gh pr merge` directly (no wrapper), or use"
              " /kbg:ship-merge.", file=sys.stderr)
        sys.exit(2)
    sys.exit(0)

# --- Resolve the review-pr state file. ---
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
    # No file matches THIS merge'\''s specific selector (pr_num unresolved --
    # bare `gh pr merge`, --squash-only, a branch name, or a URL all skip
    # the keyed lookup above, and no unkeyed review-last.json exists
    # either -- gh resolves all of those forms from the CURRENT BRANCH, not
    # from the command text, so pr_num being unset here is common, not
    # exotic). A prior version of this gate treated that as "unreviewed
    # merge, not this gate'\''s concern" and allowed unconditionally -- but
    # that can'\''t rule out this bare merge being exactly the one some OTHER
    # on-disk review already flagged non-clean. Same _any_at_risk_state()
    # backstop the ambiguous-indirection path above already uses.
    # github.com/wasikarn/kbg-harness/issues/49
    #
    # But a PLAUSIBLE PR NUMBER (pr_num matches \d+) with no keyed file for
    # it is a KNOWN, SPECIFIC PR that simply hasn'\''t been reviewed by this
    # gate'\''s ecosystem -- not ambiguous. Some OTHER unrelated PR being
    # non-clean elsewhere on disk says nothing about this one; punishing it
    # would be a false block on a target we can actually name. Restore the
    # pre-round-3 "known PR, unreviewed" -> allow semantics for that case
    # only. Genuinely ambiguous selectors (pr_num is None, a branch name, or
    # a URL -- gh resolves each of these from the current branch, not from
    # the command text) still fall through to the backstop below. A
    # value-taking flag in separated-token form, e.g. `--repo owner/repo`,
    # used to land here too until the allowlist above closed that gap.
    # github.com/wasikarn/kbg-harness/issues/51
    if pr_num and re.fullmatch(r"\d+", pr_num):
        sys.exit(0)
    if not _any_at_risk_state(state_dir):
        sys.exit(0)
    print("[kbg:gate] BLOCKED: this merge'\''s target PR could not be matched"
          " to a review state on disk (no PR number resolvable from the"
          " command -- bare invocation, a flag-only form, a branch name, a"
          " URL, or a flag value adjacent to the PR number -- or the"
          " resolved number has no state file), and at least one review"
          " state on disk is non-clean or unreadable; cannot confirm this"
          " merge is not that one. Run `gh pr merge <N>` with an explicit,"
          " unambiguous PR number, or use /kbg:ship-merge.", file=sys.stderr)
    sys.exit(2)

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

    def ci_check_passed():
        # Returns True only when CI is green or genuinely N/A (no CI
        # configured) -- every other outcome exits(2) directly from inside
        # here, unchanged from before. Factored into a function (kbg:
        # plan-reviewer Critical #2, 2026-08-15) so there is exactly ONE
        # place code can fall through to an allow -- the two separate
        # sys.exit(0) call sites this used to have would each independently
        # skip the CODEOWNERS check below, silently, for the "no CI
        # configured" case in particular.
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
            # empty + returncode 0 => repo has no CI configured => N/A => pass.
            # empty/unparseable + returncode != 0 => gh errored (auth, no PR,
            # rate limit) => unknown, NOT N/A => fail closed. (A real check
            # failure still outputs JSON with --json and exits 0; a nonzero exit
            # here means gh itself failed, not that a check failed.)
            if ci_r.returncode == 0:
                return True
            print("[kbg:gate] BLOCKED: clean review but CI status unreadable"
                  " (gh pr checks exit={}); cannot confirm CI green. "
                  "Use /kbg:ship-merge to merge -- it scores CI.".format(
                      ci_r.returncode), file=sys.stderr)
            sys.exit(2)
        if not isinstance(ci_checks, list):
            # Parseable but NOT a list (e.g. a gh error object {"message": ...}
            # some gh error/GraphQL paths emit, or any future non-array shape).
            # Fail closed: a non-list stdout is not a check result we can score,
            # and its returncode was not consulted in the is-None branch above.
            # Closes the dict-with-rc!=0 bypass (a parseable non-list used to fall
            # through to the allow). Found by the compliance-audit
            # adversarial verifier (OPEN #1); a security perimeter must not rely
            # on a subprocess stdout shape staying list-only across versions.
            print("[kbg:gate] BLOCKED: clean review but CI status unreadable"
                  " (gh pr checks returned a non-list response); cannot confirm"
                  " CI green. Use /kbg:ship-merge to merge -- it scores CI.",
                  file=sys.stderr)
            sys.exit(2)
        # ponytail: treat ALL checks (cannot filter on required: true -- gh pr
        # checks --json has no required field). SUCCESS/NEUTRAL/SKIPPED = green;
        # anything else (FAILURE, TIMED_OUT, CANCELLED, ACTION_REQUIRED, or
        # null=pending) = not green -> deny. Pending -> deny is correct: do not
        # merge while CI is running; ship-merge scores pending CI low too.
        # Ceiling: filter on required: true once gh exposes it reliably, so a
        # failing non-required check does not block. Stricter-now is the safe
        # direction (deny -> redirect to the ship-merge required-check gate).
        if ci_checks:
            bad = [(c.get("name", "?") if isinstance(c, dict) else "<non-dict>")
                   for c in ci_checks
                   if not isinstance(c, dict)
                   or c.get("conclusion") not in ("SUCCESS", "NEUTRAL", "SKIPPED")]
            if bad:
                print("[kbg:gate] BLOCKED: clean review but CI not green"
                      " -- {} not SUCCESS. Use /kbg:ship-merge to merge"
                      " (it scores CI at weight 25).".format(", ".join(bad[:5])),
                      file=sys.stderr)
                sys.exit(2)
        # empty list or all-green list => allow (empty = no CI configured for
        # this repo => N/A, not zeroed -- CI is not this repo merge model,
        # direct-push-to-develop; the check only bites when CI IS configured
        # and not green).
        return True

    if not ci_check_passed():
        sys.exit(2)  # unreachable today (ci_check_passed only returns True or
                      # exits(2) itself) -- kept so a future change to that
                      # function cannot silently fall through to an allow here.

    # --- CODEOWNERS check (2026-08-15) --- runs only once CI has passed or is
    # N/A, closing a previously-named residual gap in this file: ship-merge.md
    # step 7 CODEOWNER check only ran through markdown prose there, never
    # through this gate, so a raw ad-hoc `gh pr merge` bypassed CODEOWNERS
    # entirely even on a clean, CI-green review.
    if os.environ.get("KBG_SKIP_CODEOWNERS_GATE") == "1":
        sys.exit(0)

    # gate_dir is the directory this script lives in, resolved from $0 by the bash
    # wrapper above (argv[1] here) -- reliable in every install mode. Only
    # falls back to CLAUDE_PLUGIN_ROOT if that somehow came through empty.
    gate_dir = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else ""
    if not gate_dir:
        gate_dir = os.path.join(os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "hooks", "gates")
    lib_dir = os.path.join(gate_dir, "lib")
    sys.path.insert(0, lib_dir)
    try:
        from _codeowners_match import evaluate, discover_live
    except Exception:
        # Cannot confirm CODEOWNER approval without the matcher -- fail
        # closed, same as every other cannot-confirm branch in this file.
        print("[kbg:gate] BLOCKED: clean review but the CODEOWNERS matcher"
              " (" + lib_dir + ") could not be imported; cannot confirm"
              " CODEOWNER approval. Use /kbg:ship-merge to merge, or set"
              " KBG_SKIP_CODEOWNERS_GATE=1 if this repo has no CODEOWNERS"
              " policy to enforce.", file=sys.stderr)
        sys.exit(2)

    pv_args = ["gh", "pr", "view"]
    if pr_num:
        pv_args.append(str(pr_num))
    pv_args += ["--json", "headRefOid,files,reviews"]
    try:
        pv_r = subprocess.run(pv_args, capture_output=True, text=True, timeout=10)
    except Exception:
        print("[kbg:gate] BLOCKED: clean review but PR data unreadable"
              " (gh pr view errored/timed out); cannot confirm CODEOWNER"
              " approval. Use /kbg:ship-merge to merge.", file=sys.stderr)
        sys.exit(2)
    if pv_r.returncode != 0:
        print("[kbg:gate] BLOCKED: clean review but PR data unreadable"
              " (gh pr view exit={}); cannot confirm CODEOWNER approval."
              " Use /kbg:ship-merge to merge.".format(pv_r.returncode),
              file=sys.stderr)
        sys.exit(2)
    try:
        pv = json.loads(pv_r.stdout)
    except Exception:
        pv = None
    if not isinstance(pv, dict):
        print("[kbg:gate] BLOCKED: clean review but PR data unparseable or"
              " has an unexpected shape; cannot confirm CODEOWNER approval."
              " Use /kbg:ship-merge to merge.", file=sys.stderr)
        sys.exit(2)

    head_sha = pv.get("headRefOid")
    if not head_sha:
        print("[kbg:gate] BLOCKED: clean review but PR head SHA unreadable;"
              " cannot confirm CODEOWNER approval. Use /kbg:ship-merge to"
              " merge.", file=sys.stderr)
        sys.exit(2)
    if "files" not in pv or not isinstance(pv.get("files"), list):
        print("[kbg:gate] BLOCKED: clean review but PR file list unreadable;"
              " cannot confirm CODEOWNER approval. Use /kbg:ship-merge to"
              " merge.", file=sys.stderr)
        sys.exit(2)
    changed_files = [f.get("path", "") for f in pv["files"] if isinstance(f, dict)]
    reviews = pv.get("reviews", [])
    if not isinstance(reviews, list):
        reviews = []

    try:
        content, found, disc_error = discover_live(head_sha)
    except Exception:
        print("[kbg:gate] BLOCKED: clean review but CODEOWNERS fetch"
              " errored/timed out; cannot confirm CODEOWNER approval."
              " Use /kbg:ship-merge to merge.", file=sys.stderr)
        sys.exit(2)
    if disc_error:
        print("[kbg:gate] BLOCKED: clean review but CODEOWNERS fetch failed"
              " ({}), not confirmed absent. Use /kbg:ship-merge to"
              " merge.".format(disc_error), file=sys.stderr)
        sys.exit(2)

    if found:
        verdict, reason, detail_lines = evaluate(content, changed_files, reviews, head_sha)
        if verdict == "STOP":
            print("[kbg:gate] BLOCKED: clean review + CI green, but CODEOWNER"
                  " approval missing ({}). Use /kbg:ship-merge to merge -- it"
                  " checks CODEOWNERS too.".format(reason), file=sys.stderr)
            for line in detail_lines:
                print(line, file=sys.stderr)
            sys.exit(2)
        if verdict == "DEFERRED":
            # Cannot verify a team/email owner via the reviews API -- ask a
            # human right here instead of a hard block. A hard block would
            # dead-end: ship-merge.md itself resolves this exact case via
            # a human AskUserQuestion confirmation immediately before the
            # SAME `gh pr merge` command this gate intercepts, so blocking it
            # here would tell the user to run the command that just hit this
            # wall (kbg:plan-reviewer Critical #1, 2026-08-15). STOP above
            # stays a hard block -- it means "verified no," not "unknown."
            detail = " ".join(line.strip() for line in detail_lines)
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "ask",
                    "permissionDecisionReason": (
                        "CODEOWNER entry requires an unverifiable team/email"
                        " approval (" + reason + ") -- confirm a real owner"
                        " has approved before merging. " + detail
                    ),
                }
            }))
            sys.exit(0)
        # verdict == "PASS" -> fall through to the allow below.

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
' "$_gate_dir"
rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  echo "[kbg:gate] internal error (rc=$rc) — failing closed" >&2
  exit 2
fi
exit "$rc"