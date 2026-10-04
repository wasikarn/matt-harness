# Auto-merge lane

Label-gated auto-merge for low-risk PRs. The runner is `scripts/merge-lane.sh` in the dotfiles repo (spec: its `.scratch/auto-merge-lane/issue.md`); this page says what a PR needs to qualify. No model makes the merge decision.

## How a PR enters

A human adds the label `lane:auto`. That label is the per-PR authorization; an agent never applies it. Add it after the last commit, because a commit newer than the label refuses the PR.

## What the lane checks (cheap first, each refuses on its own)

1. Base is `develop`, the PR is mergeable, and the author is the owner.
2. At most 1000 changed lines (`LANE_MAXLINES`), and fewer than 100 files and fewer than 100 commits (`gh` lists at most 100 of each, so a PR that reaches the cap, or whose file list is shorter than `changedFiles`, is refused).
3. Every changed path is on the allowlist and none is on the denylist.
4. No commit is newer than the label, and the head SHA equals the pull ref the lane fetches.
5. The gauntlet re-runs green in a clean worktree of that SHA.
6. A read-only Codex verdict passes `check-verdict.py` and is a clean pass (`pass`, `scope_ok`, no findings, no unexpected files). It can only add a refusal, never override one.
7. A final re-read of the PR just before merging: if the label was removed, the head moved or the base changed while the checks ran, the lane prints `SKIPPED` and does not merge.

Then the lane runs `gh pr merge --merge --match-head-commit <sha>` and comments the evidence. A failed check comments the reason, removes the label and notifies. A transient problem (network, missing tool, mergeable `UNKNOWN`, timeout) defers: it notifies and keeps the label for the next run.

## Paths

| | Paths |
|---|---|
| Allowed | `docs/*`, `*.md`, `skills/*/references/*` |
| Denied | `hooks/*`, `scripts/*`, `agents/*`, `.github/*`, `.claude-plugin/*`, `*SKILL.md`, `*CLAUDE.md`, `*AGENTS.md`, `rules/*`, `*/rules/*`, `*settings*`, `*.env`, `*.env.*`, `*secret*`, `*credential*`, `*.pem`, `*.key`, `*id_rsa*`, `*hooks.json` |

`tests/*` is not on the allowlist, so a test script is refused: the gauntlet executes the tests with the owner's HOME before any verdict exists. A Markdown file under `tests/` still passes through `*.md`.

A path matching neither list is refused. The denylist wins when a path matches both.

## Try it without merging

`merge-lane.sh --dry-run` runs every check and writes nothing to GitHub.
