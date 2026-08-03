---
name: pr
description: "PR the branch on GitHub, templated body previewed before submit. Trigger on 'open a PR/เปิด PR'. Don't use for merging (`/ship-merge`) or review replies (`/address-review`)."
allowed-tools: AskUserQuestion Read Glob Grep Bash(gh pr *) Bash(gh repo view *) Bash(git push *) Bash(git log *) Bash(git diff *) Bash(git status *) Bash(git branch *) Bash(git remote *) Bash(git fetch *) Bash(git rebase *)
metadata.origin: kbg-native
---

# Create Pull Request

Create a GitHub PR from the current branch with a **consistent, templated body** that the
user sees and approves **before** the PR exists. The preview-confirm gate (Phase 4) is the
point of this skill: it enforces the body format and is the in-flow confirmation an
unflagged external-write surface requires (same posture as `kbg:review-pr`'s submit gate).

**Use when** the user says "create/open/raise a PR", "เปิด PR", "PR ให้หน่อย", or asks to
turn the current branch's commits into a pull request.

**When NOT to use:**
- Merging a reviewed PR → `/ship-merge`.
- Replying to reviewer comments → `/address-review`.
- Reviewing a PR's code → `kbg:review-pr`.

**Done when:** a PR exists on the base branch with a body that matches the template below (or
the repo's `.github` template merged with it), the user confirmed the body before creation,
and Phase 6 reported the number + URL + CI state.

**Input**: optional base-branch name and/or flags (e.g., `--draft`), from the user's request.

**Parse the request**:
- Extract any recognized flags (`--draft`).
- Treat remaining non-flag text as the base branch name.
- **Hotfix guard:** if the current branch matches `hotfix/*` and no base branch was given —
  STOP and ask for the base **before doing anything else** (don't proceed into Phase 2 to
  build a title/body/command and present the missing base as a footnote on an
  otherwise-finished recommendation — a fully-built, ready-to-fire PR anchors a skimming user
  toward agreeing with whatever base you guessed, which defeats the point of asking). A
  hotfix PR targets the **production branch** it was cut from (usually `main`); the repo
  default branch is often the integration branch (`develop`) or a stale legacy branch, so a
  silent default misroutes the fix just as effectively as a persuasive wrong guess does.
- If no base branch given (non-hotfix), resolve the repo's actual default branch (don't
  assume `main`):
  ```bash
  gh repo view --json defaultBranchRef -q .defaultBranchRefName 2>/dev/null \
    || git remote show origin | awk '/HEAD branch/ {print $NF}'
  ```
  If both return nothing usable (`(unknown)`, empty, or a branch name that doesn't actually
  exist — a stale or dangling remote `HEAD` symref, which happens on a freshly-mirrored or
  partially-configured remote), don't guess: list what actually exists (`git branch -a`) and
  use `git merge-base` between the current branch and each candidate to find which one it
  really forked from. If more than one candidate is still plausible after that, ask the user
  rather than picking one silently — a wrong default here is exactly as costly as the hotfix
  guard's wrong default above, it's just rarer.

---

## Phase 1 — VALIDATE

Check preconditions:

```bash
git branch --show-current
git status --short
git log origin/<base>..HEAD --oneline
```

| Check | Condition | Action if Failed |
|---|---|---|
| Not on base branch | Current branch ≠ base | Stop: "Switch to a feature branch first." |
| Clean working directory | No uncommitted changes | Warn: "You have uncommitted changes. Commit or stash first." |
| Has commits ahead | `git log origin/<base>..HEAD` not empty | Stop: "No commits ahead of `<base>`. Nothing to PR." |
| No existing PR | `gh pr list --head <branch> --json number` is empty | Stop: "PR already exists: #<number>. Use `gh pr view <number> --web` to open it." |

If all checks pass, proceed.

---

## Phase 2 — DISCOVER

### PR Template

Search for a repo PR template in order:

1. `.github/PULL_REQUEST_TEMPLATE/` directory — if it exists, list files and let the user
   choose (or use `default.md`).
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `.github/pull_request_template.md`
4. `docs/pull_request_template.md`

If a repo template is found, **merge** it with the kbg body structure below — don't silently
defer to it and don't discard it. Fill the repo template's sections from the commit/file
analysis; if it's missing a section the kbg structure has (e.g. **Testing**), append that
section. If a repo section already covers the same ground as a kbg section (e.g. a repo
"Why?" vs kbg's Summary, or "What changed?" vs Changes), fold the kbg content into the
repo's section rather than keeping both — that still counts as "merge," not deletion; Phase
4's "preserve every section" rule means don't drop a kbg section that has no repo-template
equivalent, not that every kbg heading must appear verbatim alongside a repo heading covering
the same thing. (Reason: a `gh pr create --body` call overrides GitHub's auto-inserted template
entirely, so "just let the repo template apply" loses the structure for model-created PRs.)

### Commit Analysis

```bash
git log origin/<base>..HEAD --format="%h %s" --reverse
```

Determine:
- **PR title**: conventional-commit format with a type prefix — `feat: ...`, `fix: ...`, etc.
  - If multiple types, use the dominant one. If a single commit, use its message as-is.
- **Change summary**: group commits by type/area.

### File Analysis

```bash
git diff origin/<base>..HEAD --stat
git diff origin/<base>..HEAD --name-only
```

Categorize changed files: source, tests, docs, config, migrations.

### Planning Artifacts

Check `docs/plans/` (single-repo plan-file convention) for a plan this PR executes.
Reference it in the PR body if one exists.

---

## Phase 3 — PUSH

```bash
git push -u origin HEAD
```

If push fails due to divergence:
```bash
git fetch origin
git rebase origin/<base>
git push -u origin HEAD
```

If rebase conflicts occur, stop and inform the user. Never `--force`; if a force is truly
needed after a clean rebase, use `git push --force-with-lease`.

---

## Phase 4 — PREVIEW → CONFIRM → CREATE

This is the format-enforcement gate. Build the body, show it, get one confirmation, then create.

### 1. Build the body

Fill this structure (or the merged repo template from Phase 2) from the Phase 2 analysis.
Preserve every section — leave a section as `N/A` rather than deleting it. (A kbg section
already folded into an equivalent repo-template section per Phase 2 isn't "deleted" — see
Phase 2's merge guidance.)

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

### 2. Confirm (the gate)

Render the **complete** proposed title + body to the user, then confirm with a single
`AskUserQuestion` before creating — this is the in-flow gate; **do not ask twice**:

- `Create the PR with this body (best when the body reads correctly)`
- `Edit the body first (best when a section is wrong or thin)`
- `Cancel (best when this shouldn't be a PR yet)`

On "Edit", apply the user's change and re-render once; on "Cancel", stop.

### 3. Create

Write the confirmed body to a temp file and pass it via `--body-file` — don't inline it with
`--body "<text>"`. Bash double quotes don't stop backtick or `$()` expansion, and a PR body
describing code almost always contains backtick-wrapped inline code (standard markdown); an
inlined `--body` breaks or executes shell content straight out of the diff/commit text, on
completely ordinary input, no adversarial commit message required. The same risk applies to
the title (it's a commit subject, and commit subjects can contain the same characters) — lower
odds since conventional-commit titles are short and rarely carry backticks, but the fix costs
nothing, so capture it into a variable through the same quoted-heredoc technique instead of
inlining it either.

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

---

## Phase 5 — VERIFY

```bash
gh pr view --json number,url,title,state,baseRefName,headRefName,additions,deletions,changedFiles
gh pr checks --json name,state,bucket 2>/dev/null || true
```

---

## Phase 6 — OUTPUT

Report to the user:

```
PR #<number>: <title>
URL: <url>
Branch: <head> → <base>
Changes: +<additions> -<deletions> across <changedFiles> files

CI Checks: <status summary or "pending" or "none configured">

Artifacts referenced:
  - <any PRDs/plans linked in PR body>
```

**Suggested next step:**
- Needs review           → `kbg:review-pr`
- Reviewed, ready to land → `/ship-merge <number>`
- Reviewer left comments  → `/address-review <number>`
- Open in browser         → `gh pr view <number> --web`

---

## Edge Cases

- **No `gh` CLI**: Stop with: "GitHub CLI (`gh`) is required. Install: <https://cli.github.com/>"
- **Not authenticated**: Stop with: "Run `gh auth login` first."
- **Force push needed**: after a clean rebase use `git push --force-with-lease` (never `--force`).
- **Multiple PR templates**: if `.github/PULL_REQUEST_TEMPLATE/` has multiple files, list them
  and ask the user to choose.
- **Large PR (>20 files)**: warn about size; suggest splitting if changes are logically separable.

## Design checks

- **Completion criterion**: PR exists with a template-matching body the user confirmed pre-creation (see "Done when" above).
- **No-op test**: no commits ahead of base, or a PR already exists → Phase 1 stops; nothing is created.
- **Failure-mode guard**: the Phase 4 confirm gate blocks `gh pr create` until the user approves the body, so an off-template or wrong-base PR can't be created silently.
