# Post-Mortem: The Sync-Seam Tokenizer Bypass Family (gh-122-134)

## 1. Summary
Five gate scripts (`irrecoverable.sh`, `main-exec-guard.sh`, `worktree-guard.py`/`verifier-protect.sh`, `merge-door.sh`) each hand-copy their own bash-command-normalization logic, per this repo's deliberate "sync-seam, no shared helper" convention. Between 2026-08-14 and 2026-09-03, the same bug class — a bash construct that vanishes to nothing once bash actually parses it (a line continuation, a comment, a command substitution with a no-op body) survives as literal characters in a gate's substring/exact-match check, letting an obfuscated command slip past — was found and fixed independently in each copy, across issues #122–#130 and five commits (v0.68.603–v0.68.607). Four related issues remain open (#129, #131, #132, #133); a fifth (#134) has a citable prior finding that may already answer its own open question. No live exploitation occurred; every instance was caught by fresh-context adversarial review before shipping.

## 2. Symptom
These are local pre-commit/pre-push security gates in a single-operator repo, not a production service — there was no user-facing incident. The observable pattern was in the review process itself: each fresh-context review of one gate's fix, tasked only with verifying that specific fix, instead found a structurally identical bypass — either a missed marker spelling in the same file, or the same normalization gap in a sibling file that hand-copies the same logic. No gate was bypassed by a real destructive command outside a deliberate, controlled ground-truthing test.

## 3. Root Cause (Mechanism)
Two combined mechanisms:

**(a) Zero-width bash constructs defeat raw-string matching.** A `\` immediately before a newline (odd backslash count) vanishes as a line continuation; a `#comment` consumes everything to the next real newline regardless of preceding escapes; `` `...` ``, `$(...)`, `${x}` (x unset), `$'...'` (ANSI-C quoting), and `$@`/`$*` (zero positional parameters) can all resolve to empty or splice two adjacent tokens into one. Any gate classifying a command by exact-match or substring-match on the RAW, unparsed string is vulnerable: `` gi`true`t `` is bash-equivalent to `git` but never literal-matches `git` in the raw string.

**(b) The fix pattern applied first, each time, was marker enumeration** — list the specific vanishing spellings seen so far and gate on their literal presence. This is a blocklist against an open-cardinality class: every review round that specifically hunted for "another way to make something vanish" found one (backtick/`$(` → `${`/`$'` → `$@`/`$*`), because enumeration proves nothing about untried spellings. The fix converged, after three incomplete rounds, on the correct shape: `case "$_input" in *'`'*|*'$'*) _has_subst=1 ;; esac` — characterize the superset (any bare `$` or backtick) and defer to the accurate parser, rather than resolving the construct in bash.

## 4. Symptom Linkage
Because five gates independently re-derive the same normalization step, the same category-(a) bug had five independent chances to be introduced, and was: `irrecoverable.sh` (#122), `main-exec-guard.sh` (#123), `worktree-guard.py`/`verifier-protect.sh` (#124), and `merge-door.sh` (#126) all carried a version of the same continuation-preservation bug. `verifier-protect.sh` (#128/#130) and `merge-door.sh` (#132, still open) independently carried the command-substitution-splicing bug. Category-(b)'s enumeration weakness then meant a reviewed, shipped fix for one file's copy did not transfer to its sibling's, and did not fully close even its own file's instance until the third round.

## 5. Fix
Five commits on `develop`, in order:
- `d1e304ec` (v0.68.603) — comment-swallow bypass, `main-exec-guard.sh` + `irrecoverable.sh`.
- `33651372` (v0.68.604) — whitespace-less continuation bypass, `irrecoverable.sh` (#122).
- `5e1d6c77` (v0.68.605) — line-continuation bypasses, `main-exec-guard.sh` + `worktree-guard.py` + `verifier-protect.sh` (#123, #124).
- `9749a43b` (v0.68.606) — `verifier-protect.sh` backslash-continuation bypass (#125) + `irrecoverable.sh` command-substitution-splicing hardening.
- `0233a9be` (v0.68.607, committed, **not yet pushed**) — `merge-door.sh` continuation bypass (#126); `verifier-protect.sh` case-sensitivity (#127) and splicing (#128, #130); both files' splicing guards generalized to the superset form.

## 6. Discovery Method
Every instance was found the same way: a freshly-dispatched reviewer agent with no memory of the implementation, tasked only with verifying one specific fix, instead traced the fast-path logic far enough to construct a new bypass the fix didn't cover. This recurred at least five times in this family. No static analysis, fuzzer, or automated check found any of these — every discovery was a manual, adversarial payload construction, ground-truthed against real bash execution.

## 7. Escape Reason
No cross-file consistency check verifies that two independently-hand-copied normalization steps stay equivalent, and no property-based test or fuzzer exercises "does any zero-width bash construct survive this substring check" as a general property — every regression test added is a fixed example, not a property (confirmed: `grep -rl "fuzz\|property" tests/hooks/` — zero hits). The sync-seam convention's stated rationale (avoid a shared-helper single point of failure, given 2 prior self-inflicted lockouts from editing this region — `irrecoverable.sh:16-21`, `verifier-protect.sh:79-84`) traded one risk for another: it removed the risk of one bug breaking every gate at once, but removed with it any mechanism that would catch the same bug present in multiple copies, or fixed in one copy and not its sibling. No harness-audit check enforces the sync-seam comments' own instruction ("if either file's normalize step changes, check the other") — confirmed: `grep -rl "sync-seam" skills/meta/harness-audit/` — zero hits.

## 8. Validation Proof
- `tests/hooks/test-gates.sh`: 250 → 252 (#122) → 254 → 256, all green.
- `tests/hooks/test-verifier-protect.sh`: 33 → 40 (#125) → 50 (#127/#128/#130) → 52, all green.
- `tests/hooks/test-merge-door.sh`: 20 → 24 (#126), all green.
- `scripts/run-gauntlet.sh` green at every ship point; harness-audit 0 CRIT/0 WARN at v0.68.607.
- Each round's regression tests were confirmed red-before/green-after by the fixer and independently re-run by a fresh-context reviewer, not trusted from the fixer's own report alone.

## 9. Follow-Ups
- [ ] #129 — python3's own tokenizer still can't resolve a spliced argv0 back to its real value even once a command correctly defers to it; neither backtick nor `$(...)` payloads are denied end-to-end anywhere today. Owner: Unowned — needs assignment. Done when: a fix closes this in at least `irrecoverable.sh`, with a test proving the deny actually fires.
- [ ] #132 — `merge-door.sh` never received the `$`/backtick superset guard; ground-truthed twice as exploitable. Owner: Unowned — needs assignment. Done when: the guard is ported with a red-before/green-after test.
- [ ] #131 — `merge-door.sh`'s comment-swallow gap (same class as the 2026-08-14 fix elsewhere) was never ported. Owner: Unowned — needs assignment. Done when: ported with a regression test.
- [ ] #133 — `merge-door.sh`'s `_newlines_to_seps` uses a parity-blind `\\\n` regex, unlike `irrecoverable.sh`'s parity-aware scanner. Owner: Unowned — needs assignment. Done when: a repo-wide grep for the naive regex shape is run and every hit upgraded or explicitly waived.
- [ ] #134 — `verifier-protect.sh:78` already states, as a design note dated 2026-08-14 (before #134 was filed), that the Claude Code JSON serializer emits ASCII alphanumerics literally. This directly speaks to #134's own stated open question (whether the real serializer ever emits `\uXXXX` for plain ASCII) without further investigation. Owner: Unowned — needs assignment. Done when: #134 is either closed citing this note, or reopened with evidence the 2026-08-14 finding was wrong.
- [ ] No property-based/fuzz test exists for "does any zero-width-vanishing bash construct survive this gate's substring check" — the exact recurring failure mode. Owner: Unowned — needs assignment. Done when: at least one such test exists for one gate, as a template.
- [ ] No mechanism enforces the sync-seam comments' own "if either file's normalize step changes, check the other" instruction — currently a human note, not a check. Owner: Unowned — needs assignment. Done when: a lint/audit check flags a sync-seam file changed without its documented sibling changing in the same commit, or the convention is explicitly revisited instead.

## 10. Assumption Trace
The sync-seam comments in `irrecoverable.sh:16-21` and `verifier-protect.sh:79-84` are contemporaneous artifacts — dated 2026-08-14, before this bug family's own discovery began — stating the belief actually held when "no shared helper" was decided: "a shared-helper bug would break [gates] simultaneously; editing this exact fast-path cost 2 self-inflicted lockouts before it landed clean." The belief in force was that the dominant risk was a **shared-code failure** (one bug taking down every gate at once, or a syntax lockout from a file everyone depends on) — not a **divergent-code failure** (the same bug shipping independently, and independently incompletely, in every copy). This was reasonable given the lockout history it cites. It was proven incomplete by this session's own pattern: #122/#123/#124/#126's near-identical bugs, and all three incomplete marker-enumeration rounds, are divergent-code failures the sync-seam decision did nothing to prevent — it correctly avoided its named risk and was silent on the one that actually recurred.
