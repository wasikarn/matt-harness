# git-flow-next adoption audit (2026-10-05)

**Date:** 2026-10-05
**Source:** https://git-flow.sh/docs/ (About, Quick Start, Commands, Configuration pages; the Cheat sheet page is only a download link), fetched raw with `curl` and read 2026-10-05. The tool itself, git-flow-next 2.1.0 from Homebrew, is already installed on this machine and was exercised in throwaway clones. No pinned source revision: the docs carry no version stamp beyond what `git flow version` prints.
**Verdict:** Do not adopt. The repo's branch-and-ship model (a `claude/` branch, a PR into protected `develop`, `scripts/merge-pr.sh`) has no step that git-flow-next's `finish` or `integrate` can take over: both merge locally and the tool has no PR step, while `develop` accepts only PR merges. Every preset creates a `main` this repo does not have. The tool is invisible to the `irrecoverable` gate, so its force-deletes and `--push` would run unchecked. The only parts with any value here, `start --worktree` and `delete --fetch` cleanup after a PR merge, duplicate what Claude Code worktrees and the remote's branch auto-delete already do. The pain that drives this repo's workflow (develop moving, gauntlet load, stale heads) is not something the tool addresses.
**Score:** 39/100 — **FAIL** (threshold 65; two criteria below the 40% floor; confidence medium). Full criteria table: see Decision score below.

Every claim below about the source's internals is what it describes as of this read, not a verified fact about the source as it exists today or in the future.

## Method

Three agents plus the host, all read-only against the repo. Agent A extracted and tested 20 claims from the saved docs, running git-flow-next in throwaway clones of `develop` with the remote removed (no push). Agent B analyzed fit against this repo, including feeding `git flow ...` commands to `hooks/gates/irrecoverable.sh`. The attacker was Codex `gpt-6.1-sol` at medium effort in a read-only sandbox, validated through `check-verdict.py` and `check-citations.py`. That sandbox refused temp-file creation, so the attacker could not rerun Agent A's clone-based tests; it re-checked help output, docs text, repo lines and the gate, and marked the runtime items `insufficient evidence`. The host then reproduced the two claims the attacker could not (#3 and #10 below) in a fresh clone. This is a first audit of this source: `docs/research/` and the memory index had no earlier git-flow entry. No qmd collection was searched, since the source was a given URL.

The attacker's five findings are adopted as narrowings in the table and notes: `finish` with a fast-forward does not always create a commit; `start [name] [base]` accepts an explicit base, so the stale-local-develop problem is a default-only limit; "no PR concept" holds only for GitHub (the docs describe a GitLab merge-request push option on `publish`); the `overview` flags are confirmed missing; the gate gap is confirmed.

## Claim-by-claim: the docs hold on mechanics but diverge from the tool on presets, validation and overview

Legend: `MATCH` = claim confirmed against primary evidence · `PARTIAL` = partially confirmed ·
`GAP` = claim not found / contradicted by primary evidence · `N-A` = not applicable to this repo.

| # | Claim | Verified? | This repo's posture | Verdict |
|---|---|---|---|---|
| 1 | `finish` merges locally into the parent and pushes nothing by default | Yes — observed directly (Agent A: `GIT_TRACE` shows fetch, merge, branch delete; remote SHA unchanged); the attacker confirmed the docs text and `--help` only | `develop` takes PR merges only (`docs/reference/branching-model.md:3-4`), so a local finish commit on `develop` cannot be pushed | MATCH |
| 2 | Presets (classic, github, gitlab) set up a workflow for the repo | Yes — observed directly (all three create `main` from develop's tip; github and gitlab ignore `develop`) | No `main` or `master` exists locally or on origin; `origin/HEAD` is `develop` | PARTIAL |
| 3 | Config validation "prevents parent/child loops" | Yes — observed by Agent A and reproduced by the host: `init --preset=github --main=develop` writes `gitflow.branch.develop.parent develop` and `git flow update` reports success | A develop-only trunk is this repo's actual shape, so this is the case that would be hit | GAP |
| 4 | `--custom` gives full control of the branch layout | Yes — observed directly (`printf 'develop\n' \| git flow init --custom` gives a clean develop-only trunk; with stdin closed it silently creates `main`) | The only clean route to this repo's shape, and it needs interactive input | MATCH |
| 5 | A topic type's upstream strategy can be `none` (trunk only); `finish` honors the strategy | Yes — observed by Agent A and reproduced by the host: `config edit topic feature --upstream-strategy=none` is accepted and `finish` still prints `Merging using strategy: merge` | No way to make `finish` skip the merge | GAP |
| 6 | `--ff` allows fast-forward (the default) | Yes — observed directly (the trace shows a plain `git merge`; a machine-global `merge.ff=false` beats an explicit `--ff`) | This machine sets `merge.ff=false`, so `finish` and `integrate` add merge commits | PARTIAL |
| 7 | `overview --format=json\|yaml`, `--no-color`, and a health status | Yes — observed by Agent A and independently by the attacker: `--format=json` and `--no-color` both exit 1 with `unknown flag`; plain `overview` prints no health status (docs: `idea-audit-source-gitflow-next-commands.html:176-181`) | No existing equivalent, and no need found | GAP |
| 8 | `start` and `finish` fetch by default; `finish` aborts when the parent or topic has diverged from its remote | Yes — observed directly; `start` still branches from the configured local start point (docs: `idea-audit-source-gitflow-next-commands.html:395`), though `start [name] [base]` accepts an explicit base | Local `develop` runs behind `origin/develop` while peers merge (60 merges in 24 hours on `origin/develop`, Agent B); an explicit base avoids it | PARTIAL |
| 9 | Conflicts: state saved, `--continue` or `--abort` resumes | Yes — observed directly (rc=3, state in `.git/gitflow/state`, abort restores, continue completes) | Real, but only for local merges this repo does not do | N-A |
| 10 | `start --worktree` creates a managed worktree; `finish` removes managed ones and leaves hand-made ones | Yes — observed directly; Claude Code's own worktrees list as `(unmanaged)` | `.claude/worktrees/` and `EnterWorktree` already provide this (`docs/reference/branching-model.md:64-66`) | MATCH |
| 11 | `delete --fetch` removes a branch merged remotely (a GitHub PR merge) without `--force` | Yes — observed directly against a simulated PR merge on a local bare remote | The remote already deletes merged branches (`docs/reference/branching-model.md:11`); local cleanup is by hand (12 stale `claude/` branches, 10 leftover worktrees, Agent B) | MATCH |
| 12 | Hooks `{pre,post}-flow-<type>-<action>` with avh arguments; a failing pre-hook blocks | Yes — observed directly (rc=3, no branch created); `gitflow.path.hooks` overrides | `.git/config` already holds a `gitflow.path.hooks` pointing at a directory that no longer exists, so flow hooks would silently never run | MATCH |
| 13 | avh config is translated at runtime without modifying settings | Yes — observed directly: `feature start` works with legacy keys; `init` imports and adds about 59 new keys, keeping the legacy ones | `.git/config` has legacy `gitflow.branch.develop develop` and `gitflow.branch.master master`; no `master` branch exists, so `integrate develop` and `release finish` fail | PARTIAL |
| 14 | The repo's `irrecoverable` gate sees `git flow` commands (a host question, not a source claim) | Agent B fed commands to `hooks/gates/irrecoverable.sh`; `git flow feature finish x --push`, `... --force-delete --force-worktree`, `git flow feature delete x --force`, `git flow integrate develop` and `git-flow feature finish x --no-verify` are all allowed, while `git flow feature finish x --no-verify` is denied (the attacker repeated this check) | `irrecoverable.py` only inspects commands whose program is `git` with a known subcommand (`hooks/gates/irrecoverable.py:2092`, `:1615`); a config `gitflow.<type>.finish.noverify` skips hooks with no flag in the command | GAP |
| 15 | `finish --push` and `publish -o merge_request.create` push or open merge requests | Author-asserted: not run (no-push rule); the attacker confirmed the GitLab push option in the docs only | The workable path is start, push the branch yourself, `gh pr create`, merge on GitHub, `feature delete --fetch` | N-A |

## Shipped

Nothing — this is a read-only research pass. The only artifacts are this file and a memory pointer. The throwaway clones were trashed; the real repo's `.git/config` was not changed.

## Deliberately not shipped

- **Adopting git-flow-next as the branching tool** — `docs/reference/branching-model.md:3-4` (protected `develop`, PR required) and `scripts/merge-pr.sh:25-32` (base must be develop, PR head must contain `origin/develop`) already cover start-to-merge; YAGNI, and the composer-not-creator rule (`docs/reference/composer-not-creator.md`: add a surface only when none fits, and the existing one fits). Labeled: **declined on evidence**.
- **A `flow` rule in `hooks/gates/irrecoverable.py`** — the gate misses `git flow` today (`hooks/gates/irrecoverable.py:1615`), but nothing in the repo uses the tool, so the rule would guard an unused surface; `docs/reference/operating-model.md` §1 (a rule needs a real past mistake to fail on). Labeled: **deferred**.
- **Using only `start --worktree` and `delete --fetch`** — Claude Code worktrees already cover the first (`docs/reference/branching-model.md:64-66`) and the remote auto-deletes merged branches (`:11`); adding a Go binary and a `gitflow.*` config for local branch cleanup is a poor trade (YAGNI). Labeled: **declined on evidence**.
- **Cleaning the stale `gitflow.*` keys already in local `.git/config`** (including `gitflow.path.hooks` pointing at a missing directory) — nothing reads them today, they are the operator's local config, and removing them is a one-line config edit the gate may block; not a repo change. Labeled: **deferred**.

## Decision score (METHODOLOGY Rule 14)

Scale per criterion is 0-10. Anchors for this source: **primary-source-fidelity** 3 = most doc claims contradicted when run, 6 = most hold with a handful of named contradictions, 9 = every claim reproduces. **fit** 2 = no unmet need and the model conflicts with the repo's rules, 5 = a real need partly met, 9 = a stated pain it removes. **blast-radius/reversibility** (higher = safer to adopt) 3 = unchecked by gates and leaves config and branches behind, 6 = leaves a little config and is easy to undo, 9 = no state changes and nothing to undo.

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| primary-source-fidelity | 40 | 6/10 | Largest weight so a confident total cannot rest on shaky evidence. 15 of 20 tested claims hold; 5 are contradicted or partial (presets, loop validation, `none` strategy, `--ff`, `overview`); two were reproduced independently by the host, one by the attacker. |
| fit | 30 | 2/10 | The tool answers "how do I manage git-flow branches"; this repo's need is "ship PRs safely while develop moves". No unmet need found by grep or by the post-mortem list; the model conflicts at `finish`, and no `main` exists. |
| blast-radius/reversibility | 30 | 3/10 | A trial in the real repo adds about 58 `gitflow.*` keys, a local `main`, and a changed parent for `develop`; a `--push` would create `main` on origin. The gate cannot see the tool, and a pushed branch cannot be pulled back. Weight 30 because cost-if-wrong is real but a clone trial is cheap. |

Weighted sum: (6×40 + 2×30 + 3×30) / 10 = 39.0 = **39/100** (computed by `scripts/_lib/weighted-score.py`). Pass threshold 65 (this audit's own number: a clear majority on the weighted axes, not a bare pass); fatal-weakness floor 40% of each axis's max. **fit** (20%) and **blast-radius/reversibility** (30%) are below the floor, and the source side did not trip the all-`insufficient evidence` trigger. **FAIL.** Confidence: medium (one independent Codex pass whose sandbox could not rerun clone tests, offset by the host reproducing the two key runtime claims; results are specific to git-flow-next 2.1.0 and a repo with a `develop` trunk and no `main`).

## Open questions

- Does `finish --push` or `publish` behave as documented against a real remote? Not run here (no-push rule); revisit only if someone proposes using those commands against a scratch remote.
- Would a `main` trunk change the fit? Revisit only if the repo ever adds a `main` or `master` branch or a release-branch process (today a release is a `chore: bump mh to X` PR and there are no tags on origin).
- Does a later git-flow-next release add PR awareness or fix the `overview` flags and the self-parent validation? Revisit only if a release note says so, not from re-reading these docs.
- Another session changed the manifest version in the shared working tree (1.1.187 to 1.1.188) while the attacker ran; the attacker's sandbox is read-only and the manifests are shared across sessions, so this is read as a peer bump, not an attacker write.

<!-- Reserved: a later pass appends a dated correction here, never rewrites the sections above.
**Correction (date, mechanism):** ... -->
