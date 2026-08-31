---
name: ship-release
description: "Ship a release: bump, changelog, review gate, tag, merge, monitor."
argument-hint: "[major|minor|patch|version]"
disable-model-invocation: true
disable-model-invocation-reason: irreversible external — cuts a release (tag/merge/publish)
model: inherit
effort: high
---

# Ship Release

Cut a release from the current branch. This orchestrates version bump, changelog, final verification, tag, and merge — with gates at each step.

**When to use / not:** use when cutting a release. Don't use for PR merges (`mh:ship-merge`) or
hotfixes.

## Core Principles

- **Reproducible builds.** The release must be cut from a clean, known state. Pin the commit SHA.
- **Changelog is human-readable.** Not a git log dump — curated, categorized, with breaking changes highlighted.
- **Tag = contract.** Once pushed, a version tag is immutable. Verify twice before pushing.
- **Monitor after deploy.** A release isn't done when the tag is pushed; it's done when telemetry is green.

---

## Phase 1: Prepare

**Goal**: Confirm what's in this release and pin the state.

**Actions**:
1. Check whether the user specified a version bump type (`major` / `minor` / `patch`) or an
   exact version when invoking this skill.
   Also sanity-check any branch name implied by the request against what the repo actually has
   (e.g. a task mentioning "develop" when the repo only has `main`) — release off the branch
   that actually contains the commits, and say so if it differs from what was assumed.
2. If no version specified, compute next version from current tags: `git describe --tags --abbrev=0` → bump per semver.
   **If this fails because no tags exist yet (first release), that's not a semver diff — it's an
   initial-version choice.** Default to `0.1.0` unless the project has already committed to a
   stable public API (published package, external consumers, a versioned contract) — in which
   case `1.0.0` is the more honest starting point. State which case applies and why, rather than
   picking silently. **Revisit if**: the project commits to a stable public API shortly after a
   `0.1.0` first release — the *next* release should reconsider whether `1.0.0` is now the more
   honest number, not mechanically continue bumping off `0.1.0`.
3. Pin release commit: `RELEASE_SHA=$(git rev-parse HEAD)`.
4. Generate changelog draft from commits since last tag:
   - `git log $(git describe --tags --abbrev=0)..HEAD --oneline`
   - Categorize: Features, Fixes, Breaking Changes, Internal
5. Present to user: proposed version + changelog draft + `RELEASE_SHA`.
6. **Analyze**: changelog completeness (all user-facing changes captured?), semver correctness (breaking changes → major, features → minor, fixes → patch), CI status on `RELEASE_SHA`. **Recommend** confirm when changelog is complete and semver is correct; recommend revise when categorization looks off. **Self-consistency**: don't let a soft or hedged Recommend stand in for a clear one — if Analyze found a concrete problem (categorization off, commits missing, CI red), say so plainly and recommend revise. This never skips the ask below: Phase 1 gates the irreversible tag/merge/publish this command exists to confirm (see this file's `disable-model-invocation-reason`), so the ask always fires regardless of how clear the recommendation is — a firm Recommend just means the user's confirm is fast, not that it's skipped.
7. **AskUserQuestion** single-select: "Phase 1 ready: release [version] at [RELEASE_SHA] with [N] changes in the changelog. Proceed?"
   - `Confirm and proceed (best when changelog is complete, semver is correct, and CI on RELEASE_SHA is green)` — moves to Phase 2 (Bump); version files get edited and a bump commit is pushed
   - `Revise version or changelog (best when categorization is off, commits are missing, or CI is red)` — stays in Phase 1, redo the affected step, re-run this ask
   - `Abort — not releasing today` — stop the command entirely, nothing is written or pushed

**Next**: Phase 2 (Bump).

---

## Phase 2: Bump

**Goal**: Update version files and changelog.

**Actions**:
1. Update version in relevant files (e.g., `package.json`, `Cargo.toml`, `version.go`, `pyproject.toml`, etc.):
   - Detect project type from files present.
   - Use `npm version`, `cargo set-version`, `poetry version`, or manual edit as appropriate.
2. Write/append to `CHANGELOG.md` with the curated changelog from Phase 1.
3. Commit: `chore(release): bump version to X.Y.Z`.
4. Push the version bump commit.

**Gate**: CI must pass on the version bump commit before tagging.

**Next**: Phase 3 (Final Review).

---

## Phase 3: Final Review

**Goal**: One last review before tagging — on whichever branch is actually being released.
Phase 1/2 never create a dedicated release branch, so don't assume one exists unless your
project's own convention calls for it; in a trunk-based repo, "the release branch" is just
the branch you're releasing from.

**Actions**:
1. If a dedicated release branch exists (project convention, not this command's default): tell
   user "Run `mattpocock-skills:code-review` on the release branch for a final sanity check," then wait for it.
2. If there's no separate release branch (trunk-based, releasing directly off `main`/`develop`):
   there's no separate branch to review — do a final manual read-through of the diff since
   the previous release instead (the previous tag if one exists, or the repository's first
   commit if this is the first release — Phase 1 Action 2 already determined which case
   applies), and say explicitly that this is the trunk-based path, not a silently-skipped
   review.
3. Accept only Critical findings. Minor/Important can ship if user agrees.

**Gate**: Zero Critical findings before tagging.

**Next**: Phase 4 (Tag).

---

## Phase 4: Tag

**Goal**: Create and push the version tag.

**Actions**:
1. Create annotated tag on the Phase 2 bump commit — not the pre-bump `RELEASE_SHA` pinned in
   Phase 1, which still has the old version string; the bump commit is the one that actually
   contains `vX.Y.Z`: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`.
2. Verify the tag lands on that same bump commit: `git rev-parse vX.Y.Z^{commit}` should match
   the bump commit's SHA, not `RELEASE_SHA`.
3. Push tag: `git push origin vX.Y.Z`.
4. If GitHub Releases is used, draft release notes from changelog.

**Gate**: Tag is immutable — double-check version string before pushing.

**Next**: Phase 5 (Merge / Deploy).

---

## Phase 5: Merge / Deploy

**Goal**: Land the release where it needs to be. What this means depends on which path Phase 3
took — state explicitly which case applies rather than silently assuming one.

**Actions**:
1. Dedicated release branch (from Phase 3): merge it into main/stable now (via PR or direct
   merge per project convention).
   Trunk-based, no separate release branch: this step is a no-op — the release already lives on
   main/stable by definition, nothing to merge. Say so rather than skipping the step silently.
2. If deploy is separate from merge, trigger deploy pipeline.
3. Verify CI/CD passes post-merge.

**Next**: Phase 6 (Monitor).

---

## Phase 6: Monitor

**Goal**: Confirm release health in production.

**Actions**:
1. Tell user: "Monitor for 30 minutes post-deploy. Check error rates, latency, and critical user journeys."
2. If anomalies detected, be ready to invoke `mh:incident` (hotfix path) or rollback — then `mh:post-mortem` once resolved.
3. Summarize: version shipped, tag sha, deploy status, monitoring checklist.

**Done.**

## Anti-Patterns

- **Tag before review** — Never tag before this command's own Phase 3 Gate (zero Critical findings) is satisfied.
- **Git log as changelog** — Raw commits are not a changelog. Curate and categorize.
- **Forgetting to monitor** — The release isn't done at push. Watch telemetry.
- **Patch-level breaking changes** — If a breaking change sneaks in, bump minor or major, not patch.
