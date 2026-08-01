---
name: compress-docs
description: "Compact a bloated markdown doc for tokens; verify-before-overwrite, grammar stays full. Use when over harness-audit's 20K threshold. Don't use for content grading or suggest-only scans."
metadata:
  origin: JuliusBrussee/caveman (caveman-compress skill, safety pattern adapted — compression technique is kbg-native, not caveman-grammar)
---

# Compress Docs

Fifteen-plus manual token-optimizer passes across this repo's own history (see `CHANGELOG.md`)
did the same job by hand every time: read, cut duplication/filler, verify nothing load-bearing was
lost. This skill is that process made repeatable and self-verifying, so it doesn't depend on a
fresh set of eyes remembering to diff-check the result each time.

**Not a caveman-grammar port.** `caveman-compress`'s own compression rules drop articles and lean
on fragments — that's the caveman skill's job (talk terser), and it directly conflicts with
`output-styles/staff-eng.md`'s "don't sacrifice grammar for brevity" rule. What's adapted here is
the *safety pattern* (verify byte-exact preservation of code/links, bounded retry, abort clean on
failure) — the actual compression technique is kbg's own established practice: cut duplication and
filler, keep full sentences.

## When to use / not

Use on a markdown doc (skill, command, `CLAUDE.md`-shaped file, any prose doc) that's grown bloated
— restated sentences, redundant examples, filler connectives — especially one harness-audit already
flagged over its 20K-char threshold (checks 42/51).

Don't use for:
- Grading a `CLAUDE.md`'s content completeness or currency — `claude-md-management:claude-md-improver`
  and `kbg:claude-md-health` do that; this skill only shrinks, it doesn't audit accuracy.
- A quick manual trim of one or two sentences — just edit it, this skill's overhead isn't worth it
  for a change that small.
- Non-markdown files, or code files of any kind.

## Preconditions

**Git must be the safety net.** Target file must be committed with no uncommitted changes
(`git status --short -- <file>` empty). If dirty, stop and tell the user to commit or stash first.
This skill does **not** write a `.original.md` backup the way `caveman-compress` does — git already
gives byte-exact recovery via `git checkout -- <file>`, and a parallel backup file would just be the
same safety net twice. This is a deliberate simplification, not an oversight: rung 2 of the
(`contexts/dev.md`) ladder — reuse what the codebase already has.

**Refuse anything that looks like it holds secrets.** If the filename or path suggests credentials
(`.env*`, `*secret*`, `*credential*`, `*password*`, `id_rsa`/`id_ed25519`, anything under `.ssh/`,
`.aws/`, `.gnupg/`), stop and say why instead of compressing — matches `caveman-compress`'s own hard
refuse for the same class of file. This skill is scoped to markdown docs already, so most of these
won't collide, but a hand-written runbook (`SECRETS.md`, a credential-rotation doc) is a realistic
case where real values end up pasted into prose.

## Compression rules

**Remove:**
- Sentences that restate a point already made elsewhere in the same file
- Redundant examples — keep the clearest one, cut near-duplicates
- Filler phrases carrying no information ("it's worth noting that," "in order to" → "to")
- Connective throat-clearing ("However," "Furthermore") where the logical link is already clear

**Preserve exactly — byte-for-byte, checked by the verify script:**
- Fenced code blocks (proper open/close fence matching, not just a naive scan)
- Inline code spans (occurrence-counted — losing 1 of 2 mentions of the same span still fails)
- Markdown link URLs
- Headings (count, level, and text)
- YAML frontmatter block, whole — **known failure mode, not a hypothetical:** even an LLM
  explicitly told to preserve frontmatter sometimes touches it anyway during a compression pass
  (documented in caveman-compress's own `compress.py`, which works around it by splitting
  frontmatter off before compressing and re-prepending it verbatim). Since every kbg
  skill/agent/command file opens with frontmatter, treat this as a first-class check, not an
  afterthought — don't even attempt to compress inside the `---`...`---` block.

**Preserve in full:** grammar and sentence structure. No dropped articles, no fragments — this is
where this skill diverges from its source. Preserve bullet/numbered-list nesting and tables.

**Structural option, not a requirement:** if a section is detailed-but-rarely-needed, moving it to
a `reference.md` (directory-form, see `docs/command-authoring-conventions.md`) is a valid
alternative to cutting it — this is how several of this repo's own real optimizer passes worked
(`orchestrate`, `backend-patterns`/`frontend-patterns`), not something `caveman-compress` itself
offers, since it targets arbitrary docs rather than kbg-shaped skill/command files.

## Workflow

1. **Check preconditions.** Git-clean and not a sensitive-looking path, both above. Stop if either
   fails.
2. **Compress.** Read the file, apply the rules above via `Edit`. If there's genuinely nothing to
   cut (already tight, or every sentence is load-bearing), say so and stop — don't force an edit to
   look like it did something.
3. **Verify.** Run:
   ```bash
   python3 skills/compress-docs/scripts/verify-preserved.py <file>
   ```
   It diffs the file's fenced code blocks, inline code spans, and link URLs against the
   last-committed version (`git show HEAD:<file>`), in order. Exit 0 = all protected regions
   matched; exit 1 = lists which region drifted and how.
4. **On failure:** fix only the flagged region — don't recompress from scratch. Re-run step 3.
   Bounded at 2 retries.
5. **Still failing after 2 retries:** `git checkout -- <file>` to restore the committed version,
   report the failure and what kept breaking, stop. Never leave a doc in a half-compressed,
   unverified state.
6. **On pass:** report the before/after character count and the delta. Done.

## Completion criterion

Done when the verify script exits 0 on the current on-disk file, or step 5's clean abort ran. A
compression that "looks right" but hasn't been run through the verify script is not done.
