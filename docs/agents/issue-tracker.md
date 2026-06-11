# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Per-task working directory (`.scratch/<slug>/`)

GitHub issues are canonical, but each non-trivial task also gets a local working
directory at `.scratch/<slug>/` — gitignored (working-tree only, not an audit
record). `<slug>` is the task's kebab-case name; the command workflows call the
same token `<feature>` — they are the **same directory**.

Siblings that may live there:

- `issue.md` — a local copy / working notes for the task's issue (optional).
- `ACCEPTANCE.md` — the locked acceptance contract from `/accept-task`, verified by
  `/review-pr`'s acceptance-gap check.
- `optout-reason.md` — the TDD opt-out justification when a feature/fix skips TDD.

Reuse an existing `.scratch/<slug>/` dir if one is already open for the task;
otherwise `mkdir -p .scratch/<slug>`.
