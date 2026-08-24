---
name: pr
description: "PR the branch on GitHub, templated body previewed before submit. Trigger on 'open a PR/เปิด PR'. Don't use for merging (`/ship-merge`) or review replies (`/address-review`)."
bucket: review
allowed-tools: AskUserQuestion Read Glob Grep Bash(gh pr *) Bash(gh repo view *) Bash(git push *) Bash(git log *) Bash(git diff *) Bash(git status *) Bash(git branch *) Bash(git remote *) Bash(git fetch *) Bash(git rebase *)
metadata.origin: kbg-native
model: inherit
effort: medium
---

# Create Pull Request

Create a GitHub PR from the current branch with a **consistent, templated body** the user
approves **before** the PR exists. The preview-confirm gate (Phase 4) is the point of this
skill: it enforces the body format and is the in-flow confirmation an unflagged
external-write surface requires.

**Use when** the user says "create/open/raise a PR", "เปิด PR", "PR ให้หน่อย", or asks to
turn the current branch's commits into a pull request.

**When NOT to use:**
- Merging a reviewed PR → `/ship-merge`.
- Replying to reviewer comments → `/address-review`.
- Reviewing a PR's code → `mattpocock-skills:code-review`.

**Done when:** a PR exists on the base branch with a body that matches the template
(`reference.md#pr-body-structure-phase-41`, or the repo's `.github` template merged with it),
the user confirmed the body before creation, and Phase 6 reported the number + URL + CI state.

**Input**: optional base-branch name and/or flags (e.g., `--draft`), from the user's request.

**Needs**: the `gh` CLI installed and authenticated (`gh auth status`) — `allowed-tools` above grants permission to call it, not proof it's installed or logged in.

**Parse the request**:
- Extract any recognized flags (`--draft`).
- Treat remaining non-flag text as the base branch name.
- **Hotfix guard:** if the current branch matches `hotfix/*` and no base branch was given —
  STOP and ask for the base **before doing anything else**, not as a footnote on an
  already-built recommendation. A hotfix PR targets the **production branch** it was cut from
  (usually `main`), not the repo default. Why: `reference.md#hotfix-guard-rationale`.
- If no base branch given (non-hotfix), resolve the repo's actual default branch (don't
  assume `main`) via the shared script (provenance: `reference.md`):
  ```bash
  bash skills/pr/scripts/resolve-default-branch.sh
  ```
  Exit 0 → stdout is the branch name, use it. Exit 1 → stdout starts `AMBIGUOUS: ...` —
  more than one candidate survives the `git merge-base` disambiguation; ask the user rather
  than picking silently (same wrong-default cost as the hotfix guard). Exit 2 → `UNRESOLVED`
  — no usable candidate; surface that rather than guessing.

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

If a repo template is found, **merge** it with the kbg body structure — never silently defer
to it, never discard it: fill its sections from the analysis below, append kbg sections it
lacks, fold kbg content into repo sections covering the same ground. Full merge semantics and
why `--body` overrides GitHub's auto-template: `reference.md#template-merge-rationale-phase-2`.

### Commit Analysis

```bash
git log origin/<base>..HEAD --format="%h %s" --reverse
```

Determine:
- **PR title**: conventional-commit format with a type prefix — `feat: ...`, `fix: ...`, etc.
  - If multiple types, use the dominant one **by commit count** — name the runner-up type(s)
    and the deciding count in the body's Summary (e.g. "3 `fix:` vs 1 `docs:` — `fix` wins").
    **On a tie**, don't silently pick one: state the tie in the Summary and choose the type the
    commit subjects (from the `git log` above) show as the primary change — read the actual
    messages (Conventional Commits defines no fixed severity order between types).
  - If a single commit, use its message as-is.
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

Read `reference.md#pr-body-structure-phase-41` and fill that structure (or the merged repo
template from Phase 2) from the Phase 2 analysis. Preserve every section — `N/A` rather than
deleted. (A kbg section folded into an equivalent repo-template section isn't "deleted".)

### 2. Confirm (the gate)

Render the **complete** proposed title + body to the user, then confirm with a single
`AskUserQuestion` before creating — this is the in-flow gate; **do not ask twice**:

- `Create the PR with this body (best when the body reads correctly)`
- `Edit the body first (best when a section is wrong or thin)`
- `Cancel (best when this shouldn't be a PR yet)`

On "Edit", apply the user's change and re-render once; on "Cancel", stop.

### 3. Create

Write the confirmed body to a temp file and pass it via `--body-file` — never inline it with
`--body "<text>"` — and capture the title via a quoted heredoc, not an inlined argument.
Exact commands: `reference.md#create-commands-phase-43`; why inlining breaks or executes shell
content on ordinary input: `reference.md#why---body-file-never-inline---body-phase-43`.

---

## Phase 5 — VERIFY

```bash
gh pr view --json number,url,title,state,baseRefName,headRefName,additions,deletions,changedFiles
gh pr checks --json name,state,bucket 2>/dev/null || true
```

---

## Phase 6 — OUTPUT

Report to the user using `reference.md#output-report-template-phase-6`.

**Suggested next step:**
- Needs review           → `mattpocock-skills:code-review`
- Reviewed, ready to land → `/ship-merge <number>`
- Reviewer left comments  → `/address-review <number>`
- Open in browser         → `gh pr view <number> --web`

---

## Edge Cases

Worked list (no `gh`, unauthenticated, force-push-after-rebase, multiple templates, >20-file PR): `reference.md#edge-cases`.

## Design checks

- **Completion criterion**: PR exists with a template-matching body the user confirmed pre-creation (see "Done when" above).
- **No-op test**: no commits ahead of base, or a PR already exists → Phase 1 stops; nothing is created.
- **Failure-mode guard**: the Phase 4 confirm gate blocks `gh pr create` until the user approves the body, so an off-template or wrong-base PR can't be created silently.
