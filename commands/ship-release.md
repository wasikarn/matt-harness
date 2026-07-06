---
name: ship-release
description: "Cut a release end-to-end: bump, changelog, review gate, tag, merge, monitor. Say 'ship release/ปล่อยเวอร์ชัน'. Don't use for PR merges (/ship-merge) or hotfixes (kbg:incident)."
argument-hint: Optional version-bump type (major / minor / patch) or specific version
disable-model-invocation: true
disable-model-invocation-reason: irreversible external — cuts a release (tag/merge/publish)
---

# Ship Release

Cut a release from the current branch. This orchestrates version bump, changelog, final verification, tag, and merge — with gates at each step.

## Core Principles

- **Reproducible builds.** The release must be cut from a clean, known state. Pin the commit SHA.
- **Changelog is human-readable.** Not a git log dump — curated, categorized, with breaking changes highlighted.
- **Tag = contract.** Once pushed, a version tag is immutable. Verify twice before pushing.
- **Monitor after deploy.** A release isn't done when the tag is pushed; it's done when telemetry is green.

---

## Phase 1: Prepare

**Goal**: Confirm what's in this release and pin the state.

**Actions**:
1. Parse `$ARGUMENTS` for version bump type (`major` / `minor` / `patch`) or specific version.
2. If no version specified, compute next version from current tags: `git describe --tags --abbrev=0` → bump per semver.
3. Pin release commit: `RELEASE_SHA=$(git rev-parse HEAD)`.
4. Generate changelog draft from commits since last tag:
   - `git log $(git describe --tags --abbrev=0)..HEAD --oneline`
   - Categorize: Features, Fixes, Breaking Changes, Internal
5. Present to user: proposed version + changelog draft + `RELEASE_SHA`.
6. **Analyze**: changelog completeness (all user-facing changes captured?), semver correctness (breaking changes → major, features → minor, fixes → patch), CI status on `RELEASE_SHA`. **Recommend** confirm when changelog is complete and semver is correct; recommend revise when categorization looks off.
7. **AskUserQuestion** single-select: "Phase 1 ready: release [version] at [RELEASE_SHA] with [N] changes in the changelog. Proceed?"
   - `Confirm and proceed (Recommended when changelog is complete, semver is correct, and CI on RELEASE_SHA is green)`
   - `Revise version or changelog (Recommended when categorization is off, commits are missing, or CI is red)`
   - `Abort — not releasing today`

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

**Goal**: One last review-pr on the release branch.

**Actions**:
1. Tell user: "Run `review-pr` on the release branch for a final sanity check."
2. Wait for `review-pr` to complete.
3. Accept only Critical findings. Minor/Important can ship if user agrees.

**Gate**: Zero Critical findings before tagging.

**Next**: Phase 4 (Tag).

---

## Phase 4: Tag

**Goal**: Create and push the version tag.

**Actions**:
1. Create annotated tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`.
2. Verify tag points to correct commit: `git rev-parse vX.Y.Z^{commit}`.
3. Push tag: `git push origin vX.Y.Z`.
4. If GitHub Releases is used, draft release notes from changelog.

**Gate**: Tag is immutable — double-check version string before pushing.

**Next**: Phase 5 (Merge / Deploy).

---

## Phase 5: Merge / Deploy

**Goal**: Land the release in the target branch.

**Actions**:
1. Merge release branch into main/stable branch (via PR or direct merge per project convention).
2. If deploy is separate from merge, trigger deploy pipeline.
3. Verify CI/CD passes post-merge.

**Next**: Phase 6 (Monitor).

---

## Phase 6: Monitor

**Goal**: Confirm release health in production.

**Actions**:
1. Tell user: "Monitor for 30 minutes post-deploy. Check error rates, latency, and critical user journeys."
2. If anomalies detected, be ready to invoke `kbg:incident` (hotfix path) or rollback — then `/post-mortem` once resolved.
3. Summarize: version shipped, tag sha, deploy status, monitoring checklist.

**Done.**

## Anti-Patterns

- **Tag before review** — Never tag before `review-pr` Phase 3 passes.
- **Git log as changelog** — Raw commits are not a changelog. Curate and categorize.
- **Forgetting to monitor** — The release isn't done at push. Watch telemetry.
- **Patch-level breaking changes** — If a breaking change sneaks in, bump minor or major, not patch.
