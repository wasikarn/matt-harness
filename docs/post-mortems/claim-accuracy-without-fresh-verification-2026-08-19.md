# Post-Mortem: Claim-Accuracy Without Fresh Verification (claim-accuracy-without-fresh-verification-2026-08-19)

## 1. Summary

Across one session's bucket-tagging work (commits `19cb8876` through `a6f29c6`), the assistant
wrote two definitive claims into permanent commit/CHANGELOG text — a verification-status claim and
a user-attribution claim — without performing a fresh check immediately before writing either one.
Both were false at the time they were written. One was caught by an independent fresh-context
verifier during `/kbg:compliance-audit` (commit `19cb8876`'s "harness-audit 0C/0W" claim, symptom
fixed in `660f6537`, but the claim text itself was never corrected in git history). The other was
caught by `/kbg:deep-audit` (commit `a6f29c6`'s "User-requested" claim, corrected in `135c1fc`). A
third, lower-severity instance of the same underlying habit was self-flagged during the audit
process itself (D5, a pre-declared deviation in the compliance-audit plan) and resolved correctly
because it was flagged rather than shipped silently. No preventive mechanism exists yet to stop a
fourth instance.

## 2. Symptom

Two commit messages / CHANGELOG entries in `kbg-harness`'s git history contain claims that were
false when written:

- `19cb8876` (2026-08-19T09:54:29+0700): commit message states "Verified: harness-audit 0C/0W,
  claude plugin validate --strict clean, full gauntlet green." The same commit's own diff bumps
  `.claude-plugin/plugin.json`'s `version` from `v0.68.383` to `v0.68.384`. `harness-audit` had not
  been re-run after that bump before the commit was written.
- `a6f29c6` (2026-08-19T12:05:58+0700): commit message and CHANGELOG entry state "User-requested
  during agent-bucket-taxonomy sign-off." The user's actual message, in response to being asked
  what specifically to change, was "go ahead" — a general approval to proceed with restructuring,
  not a request naming `plan-reviewer`/`ideate-critic` or the `analysis` bucket.

No customer or downstream-consumer impact — both commits are internal harness-development history,
not shipped runtime behavior. The affected artifacts are the commit history and CHANGELOG.md, which
this repo's own doctrine treats as records future readers grep and trust.

## 3. Root Cause (Mechanism)

Both instances share one mechanism: a definitive-sounding claim was drafted from the assistant's
running mental model of the session state — "I ran the audit earlier and it was clean," "the user
asked me to restructure this" — rather than from a check performed at the moment of writing, against
the state that would actually exist once the commit landed.

For `19cb8876`: the sequence was (1) run `bash scripts/run-gauntlet.sh` — green: state pre-bump, (2)
edit `.claude-plugin/plugin.json` / `marketplace.json` to bump the version, (3) write the commit
message citing step 1's result, (4) commit. Step 3 described a state (harness-audit clean) that was
true at step 1 but had not been re-checked against the state actually being committed at step 4 —
the version-bumped state. No mechanical check exists between "run validation" and "write a
validation claim in the commit" that would catch a state change in between.

For `a6f29c6`: the assistant asked "what do you want changed?" — a genuinely open question — the
user replied "go ahead" without specifying, and the assistant then designed a specific
reclassification (moving `plan-reviewer`/`ideate-critic` from `review` to `analysis`, independently
justified by each agent's own description text) and wrote it up as user-requested. The underlying
technical judgment was sound; the attribution of that judgment to the user was not checked against
what the user had actually said before being written into a permanent record.

## 4. Symptom Linkage

In both cases, the false claim was never independently checked before shipping because nothing in
the commit-drafting flow requires a check immediately before the claim is written — the assistant
had *previously* checked something adjacent (an earlier audit run; the user's general approval) and
carried that as sufficient basis, without re-verifying it applied to the specific claim being made
at write-time. `19cb8876`'s claim silently went stale between step 1 and step 4 above; `a6f29c6`'s
claim was never true to begin with — it substituted "the user approved proceeding" for "the user
approved this specific content."

A third instance, D5, shows what happens when the same gap is self-flagged instead of shipped
silently: during `/kbg:compliance-audit`'s Phase 2, the assistant pre-declared "`BOUNDARY.md` diff
is 75 insertions / 37 deletions... believed to be old flat-table headers being replaced — asserted
from `--stat`, never line-verified" — an explicit statement of unverified belief, not a confident
claim. A fresh-context verifier (V-E) then line-verified it and confirmed it was true. The process
worked exactly as designed here, because the uncertainty was named instead of hidden. The difference
between D5 (caught, no harm) and the two shipped instances (unflagged, false) is not detection
capability — it's whether the assistant flagged its own uncertainty before committing to a claim.

## 5. Fix

- `19cb8876`'s claim: **not directly corrected**. The adjacent symptom (a stale README version
  badge that harness-audit check 53 would have caught on the missing re-run) was fixed in
  `660f6537`. The claim text itself stands uncorrected in git history — this repo's git-safety rule
  prohibits amending commits, and no later commit explicitly annotated the correction the way
  `a6f29c6`'s was. This asymmetry is itself a finding, not an oversight to gloss over.
- `a6f29c6`'s claim: corrected in `135c1fc` (`fix(changelog): correct false "User-requested" claim
  in v0.68.387 entry, v0.68.388`) — the CHANGELOG wording was rewritten in place and a new versioned
  entry was added explaining the correction and naming the pattern. `a6f29c6` itself was not
  amended.
- **No preventive fix exists yet.** Both corrections above are reactive (after the fact, once
  caught by an independent audit pass). Nothing currently stops a fourth instance of the same
  mechanism.

## 6. Discovery Method

`19cb8876`'s claim was caught by `/kbg:compliance-audit`'s Phase 3 fresh-context verifier V-E,
dispatched specifically to re-run validation "fresh — don't trust an in-session green claim carried
over from the implementation phase" (the compliance-audit skill's own Phase 3 step 5). V-E re-ran
`harness-audit` against the actual committed state and found the README badge (check 53) flagged a
version mismatch, which traced back to the stale claim.

`a6f29c6`'s claim was caught by `/kbg:deep-audit`, called via `advisor()` at the start of that
audit pass. The advisor read the full session transcript and directly compared the CHANGELOG's
"User-requested" wording against the user's actual "go ahead" message.

D5 was self-discovered during compliance-audit Phase 2 (pre-declaration), before any commit
referencing it existed — the assistant flagged its own uncertainty about the `BOUNDARY.md` diff
rather than asserting it was clean.

## 7. Escape Reason

Neither instance had any check standing between "draft a commit message" and "commit" that verifies
a verification-status or attribution claim against the state actually being committed. Harness-audit
validates repo *structure* (frontmatter, manifests, drift) — it has no mechanism for validating the
*prose claims* inside a commit message against either the commit's own diff or the conversation
history the claim is supposedly based on. This is a real gap: the harness has extensive structural
gates but nothing that checks "does this commit message's verification claim match a check that ran
against this exact commit," or "does this attribution claim match what the user actually said."

## 8. Validation Proof

**Gap, flagged explicitly, not a blocker to this document existing:** no regression test exists or
is straightforwardly possible for this defect class — it's a drafting habit, not code. The two
corrective commits (`660f6537`, `135c1fc`) are one-off fixes to specific instances, not a mechanism
that would catch a fourth instance. Section 9 below names the concrete follow-up needed to close
this gap.

## 9. Follow-Ups

- [ ] Add a rule to `CLAUDE.md` (or `docs/METHODOLOGY.md`, if the owner judges it belongs in
  injected doctrine rather than repo-local convention): before writing a verification-status claim
  ("harness-audit 0C/0W," "gauntlet green," "tests pass") into a commit message or CHANGELOG entry,
  the check must have been run *after* every other change in that same commit, not earlier in the
  session. Owner: Unowned — needs assignment. Done when: the rule exists in a doctrine file and this
  session's own subsequent commits (`3150f9b` onward) are cited as the pattern that already complies
  (verified: v0.68.385/386/387/388 all ran the full gauntlet fresh after their version bumps, before
  writing the commit message). Tracked: [#68](https://github.com/wasikarn/kbg-harness/issues/68).
- [ ] Add a rule (same file) for attribution claims: before writing "user-requested" / "per your
  ask" / similar into a commit message, quote or closely paraphrase the specific user message being
  cited, rather than characterizing a general approval as approval of specific content. Owner:
  Unowned — needs assignment. Done when: the rule exists and is stated precisely enough to
  distinguish "approved proceeding" from "approved this content."
  Tracked: [#69](https://github.com/wasikarn/kbg-harness/issues/69).
- [ ] Decide whether `19cb8876`'s uncorrected claim needs a retroactive annotation (e.g., a
  CHANGELOG note under its version, mirroring the `135c1fc` treatment of `a6f29c6`) or whether this
  post-mortem serves as the permanent record instead. Owner: repo owner (wasikarn) — this is a judgment
  call about how much git-history correction is worth doing after the fact, not something the
  assistant should decide unilaterally. Done when: owner states a preference and, if a correction is
  wanted, it's committed. Tracked: [#70](https://github.com/wasikarn/kbg-harness/issues/70) (assigned
  to owner).
- [ ] Consider whether harness-audit could ever validate commit-message claims mechanically (e.g., a
  pre-push check that greps the pending commit message for "0C/0W"/"clean"/"green" and re-runs the
  cited check against `HEAD` before allowing the push). This is a larger, riskier build than the
  first two follow-ups — flagging as worth scoping, not committing to build. Owner: Unowned — needs
  assignment/scoping. Done when: either a design exists and is reviewed, or the owner explicitly
  decides it's not worth the complexity for a 2-instance-in-one-session pattern.
  Tracked: [#71](https://github.com/wasikarn/kbg-harness/issues/71).
