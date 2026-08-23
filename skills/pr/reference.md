# pr — reference (templates + rationale)

Detail moved verbatim from SKILL.md (2026-08-23, 200-LOC cap refactor). SKILL.md keeps every
rule; this file carries the templates, exact commands, and the why behind the rules.

## Hotfix-guard rationale

Don't proceed into Phase 2 to build a title/body/command and present the missing base as a
footnote on an otherwise-finished recommendation — a fully-built, ready-to-fire PR anchors a
skimming user toward agreeing with whatever base you guessed, which defeats the point of asking.
A hotfix PR targets the **production branch** it was cut from (usually `main`); the repo
default branch is often the integration branch (`develop`) or a stale legacy branch, so a
silent default misroutes the fix just as effectively as a persuasive wrong guess does.

## resolve-default-branch.sh provenance

2026-08-15 extraction — the full fallback chain SKILL.md's bullet used to describe inline, now
shared with `skills/review-pr/SKILL.md`, which previously only had the first 2 lines of it.

## Template-merge rationale (Phase 2)

If a repo template is found, **merge** it with the kbg body structure — don't silently defer to
it and don't discard it. Fill the repo template's sections from the commit/file analysis; if
it's missing a section the kbg structure has (e.g. **Testing**), append that section. If a repo
section already covers the same ground as a kbg section (e.g. a repo "Why?" vs kbg's Summary,
or "What changed?" vs Changes), fold the kbg content into the repo's section rather than
keeping both — that still counts as "merge," not deletion; Phase 4's "preserve every section"
rule means don't drop a kbg section that has no repo-template equivalent, not that every kbg
heading must appear verbatim alongside a repo heading covering the same thing. (Reason: a
`gh pr create --body` call overrides GitHub's auto-inserted template entirely, so "just let the
repo template apply" loses the structure for model-created PRs.)

## PR body structure (Phase 4.1)

```markdown
## Summary

<1-2 sentence description of what this PR does and why>

## Changes

<bulleted list of changes grouped by area>

## Files Changed

<one-line summary categorized by area, e.g. "3 migrations, 2 config files, 1 test file" —
not a per-file list; GitHub's own "Files changed" tab already shows that. At exactly one
changed file, the category count and the file name carry the same information — either form
is fine there.>

## Testing

<how the changes were tested, or "Needs testing">

## Related Issues

<Closes/Fixes/Relates to #N, or "None">
```

## Why --body-file, never inline --body (Phase 4.3)

Bash double quotes don't stop backtick or `$()` expansion, and a PR body describing code almost
always contains backtick-wrapped inline code (standard markdown); an inlined `--body` breaks or
executes shell content straight out of the diff/commit text, on completely ordinary input, no
adversarial commit message required. The same risk applies to the title (it's a commit subject,
and commit subjects can contain the same characters) — lower odds since conventional-commit
titles are short and rarely carry backticks, but the fix costs nothing, so capture it into a
variable through the same quoted-heredoc technique instead of inlining it either.

## Create commands (Phase 4.3)

```bash
body_file="$(mktemp)"
cat > "$body_file" <<'PR_BODY_EOF'
<confirmed PR body>
PR_BODY_EOF

title="$(cat <<'PR_TITLE_EOF'
<PR title>
PR_TITLE_EOF
)"

gh pr create \
  --title "$title" \
  --base <base-branch> \
  --body-file "$body_file"
  # Add --draft if the --draft flag was parsed from the request

rm -f "$body_file"
```

## Output report template (Phase 6)

```
PR #<number>: <title>
URL: <url>
Branch: <head> → <base>
Changes: +<additions> -<deletions> across <changedFiles> files

CI Checks: <status summary or "pending" or "none configured">

Artifacts referenced:
  - <any PRDs/plans linked in PR body>
```

## Edge cases

- **No `gh` CLI**: Stop with: "GitHub CLI (`gh`) is required. Install: <https://cli.github.com/>"
- **Not authenticated**: Stop with: "Run `gh auth login` first."
- **Force push needed**: after a clean rebase use `git push --force-with-lease` (never `--force`).
- **Multiple PR templates**: if `.github/PULL_REQUEST_TEMPLATE/` has multiple files, list them
  and ask the user to choose.
- **Large PR (>20 files)**: warn about size; suggest splitting if changes are logically separable.
