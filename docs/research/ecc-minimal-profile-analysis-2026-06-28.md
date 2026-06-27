# ECC minimal profile + machine-learning capability — install plan analysis

**Status:** analysis (pre-install; install command NOT executed)
**Date:** 2026-06-28
**Upstream:** ECC HEAD = `2bc924faf2f8e893bfe0af86b1931283693c30ae` (same as kbg provenance anchor)
**Source paths verified against:** `/Users/kobig/Codes/Personals/ECC/manifests/{install-profiles,install-modules,install-components}.json` and `scripts/lib/{install-manifests,install-executor}.js`

---

## 1. The exact command

```bash
npx ecc install --profile minimal --target claude --with capability:machine-learning
```

- `target=claude` (NOT `claude-project`) → writes to `~/.claude/`, never touches this repo
- `profile=minimal` → 5 modules from `manifests/install-profiles.json`
- `--with capability:machine-learning` → adds 1 module `machine-learning` (347-line SKILL.md, self-contained, no companion scripts)

---

## 2. Profile `minimal` (5 modules, 38 paths)

| Module | Cost | Paths | Lands in (target=claude) |
|---|---|---|---|
| `rules-core` | light | 1 | `~/.claude/rules/ecc/` |
| `agents-core` | light | 3 (`.agents/`, `agents/`, `AGENTS.md`) | `~/.claude/{.agents,agents,AGENTS.md}` |
| `commands-core` | medium | 3 (`commands/`, `scripts/harness-audit.js`, `scripts/skills-health.js`) | `~/.claude/commands/`, `~/.claude/scripts/{harness-audit,skills-health}.js` |
| `platform-configs` | light | 10 (`.claude-plugin/`, `.codex/`, `.cursor/`, `.gemini/`, `.opencode/`, `.qwen/`, `.zed/`, `mcp-configs/`, 2 scripts) | 7 foreign-platform paths **filtered out** for target=claude; only `.claude-plugin/`, `mcp-configs/`, 2 scripts land |
| `workflow-quality` | medium | 21 skills | `~/.claude/skills/ecc/{21 skills}/SKILL.md` |

`platform-configs` filtering behavior (`scripts/lib/install-targets/helpers.js:24-34`): paths starting with `.codex`, `.cursor`, `.gemini`, `.opencode`, `.joycode`, `.codebuddy`, `.qwen`, `.zed` are skipped when `target=claude` because each is owned by a different platform adapter.

---

## 3. `--with capability:machine-learning` resolution

**Component lookup** (`manifests/install-components.json:338-344`):

```json
{ "id": "capability:machine-learning", "modules": ["machine-learning"] }
```

**Module `machine-learning` deps** (`manifests/install-modules.json:701-729`):

```
dependencies: ["framework-language", "workflow-quality", "database", "devops-infra", "security"]
defaultInstall: false, cost: medium, stability: beta
```

**Dependency resolution** (`scripts/lib/install-executor.js` → `resolveModule` at `scripts/lib/install-manifests.js:500-690`): recursive walk with cycle detection; if dep not in requested set, it's **silently auto-pulled**. No per-module opt-out flag.

**For minimal profile + machine-learning**:
- Already in minimal: `workflow-quality` ✓
- Auto-pulled (4 missing): `framework-language`, `database`, `devops-infra`, `security`

---

## 4. Final effective plan: 10 modules, 121 paths, 92 skills

| Module | Cost | Paths | Skills added |
|---|---|---|---|
| `rules-core` | light | 1 | — |
| `agents-core` | light | 3 | — |
| `commands-core` | medium | 3 | — |
| `platform-configs` | light | 10 | — |
| `workflow-quality` | medium | 21 | 21 (council, eval-harness, tdd-workflow, verification-loop, continuous-learning-v2, configure-ecc, code-tour, ai-regression-testing, hookify-rules, e2e-testing, error-handling, strategic-compact, agent-sort, agent-introspection-debugging, plankton-code-quality, production-audit, skill-scout, skill-stocktake, iterative-retrieval, windows-desktop-e2e) |
| `machine-learning` | medium | 1 | 1 (`mle-workflow`) |
| `framework-language` | medium | 52 | 45 (python, pytorch via name-ref, fastapi, react, kotlin, golang, rust, django, laravel, springboot, …) |
| `database` | medium | 6 | 6 (clickhouse-io, database-migrations, jpa-patterns, mysql-patterns, postgres-patterns, prisma-patterns) |
| `devops-infra` | medium | 9 | 9 (cisco-ios-patterns, deployment-patterns, docker-patterns, homelab-network-{readiness,setup}, netmiko-ssh-automation, network-{bgp-diagnostics,config-validation,interface-health}) |
| `security` | medium | 15 | 14 (security-review, security-scan, security-bounty-hunter, django-security, healthcare-phi-compliance, hipaa-compliance, laravel-security, springboot-security, quarkus-security, perl-security, defi-amm-security, llm-trading-agent-security, nodejs-keccak256, evm-token-decimals) |

**Why each auto-pulled module** (cross-ref `skills/mle-workflow/SKILL.md` §"Related Skills" lines 29-35 + §"Reuse the SWE Surface" lines 43-64):
- `framework-language` → python-patterns, python-testing (MLE-03/04); pytorch-patterns (MLE-04)
- `database` → database-migrations, postgres-patterns, clickhouse-io (MLE-02/05)
- `devops-infra` → deployment-patterns, docker-patterns (MLE-07/08)
- `security` → security-review, security-scan (MLE-07/08)

---

## 5. Install layout on disk (target=claude)

Adapter: `scripts/lib/install-targets/claude-home.js`. `resolveRoot` → `~/.claude/`. Remapping (lines 12-47):

| Source path | Destination |
|---|---|
| `rules` or `rules/*` | `~/.claude/rules/ecc/...` |
| `skills` or `skills/*` | `~/.claude/skills/ecc/...` ← **all 92 skills land here** |
| `docs` or `docs/*` | `~/.claude/docs/...` |
| anything else | preserved-relative-path under `~/.claude/` |

Plus `~/.claude/.claude-plugin/` (via `nativeRootRelativePath`, `sync-root-children` strategy) and `~/.claude/ecc/install-state.json` (install receipt; consumed by `npx ecc update` / `npx ecc doctor`).

---

## 6. Conflicts and constraints

1. **Namespace**: ECC skills land at `~/.claude/skills/ecc/<name>/SKILL.md` → invoke as `ecc:<name>`. Does NOT collide with `kbg:<name>` if kbg is installed separately (different parent dirs).

2. **No hooks**: `minimal` excludes `hooks-runtime`. ECC's model-as-gate + observer-loop architecture stays out. Aligns with kbg's no-model-self-start rule (see [[ecc-everything-claude-code-mine-2026-06-20]]).

3. **No governance fabric**: minimal has no `security-bounty-hunter` filter, no advisory hooks, no audit script. ECC's hooks-runtime is what carries that — and minimal skips it.

4. **Foreign-platform paths filtered**: `.codex/`, `.cursor/`, `.gemini/`, `.opencode/`, `.qwen/`, `.zed/`, `.codebuddy/`, `.joycode/` are all dropped at filter time when target=claude (`isForeignPlatformPath` in `helpers.js:24-34`).

5. **Skill-listing budget pressure** (memory `skill-listing-budget-mechanics.md`): 92 ECC skills added to the session-start list. Cap = 1,536 + fraction 1% of least-invoked. Owner baseline = 0.08 (~2.25× headroom). ECC's 92 descs likely consume 0.5-0.8 of that headroom, dropping some least-invoked kbg/ECC skills on first session. `/doctor` is the empirical check.

6. **ECC authors validate this combo** (`skills/mle-workflow/SKILL.md:41`, verbatim):
   > *"The recommended `minimal --with capability:machine-learning` install keeps the core agent surface available alongside this skill."*

---

## 7. Cost shape

- **121 source paths** → ~92 skill dirs × ~10-30KB SKILL.md ≈ **5-10 MB** in `~/.claude/`
- **Runtime**: 92 skills added to desc-load pool
- **On-disk footprint** (ECC repo reference, `du -sh`):
  - `skills/mle-workflow/` = 24K (single SKILL.md, no companion)
  - `rules/` = 536K
  - `agents/` = 548K
  - `commands/` = 544K
  - `.claude-plugin/` = 20K
  - `scripts/install-apply.js` = 8K

---

## 8. Self-check on `mle-workflow` skill

- **Single file**: `skills/mle-workflow/SKILL.md` (347 lines) — no companion scripts, no `_lib/`
- **Frontmatter**: `name: mle-workflow`, `description: <production MLE workflow desc>`, `metadata.origin: ECC`
- **Cross-references**: 10 task simulations (MLE-01..10) covering data contract → eval → serve → canary → rollback. Tied to ECC SWE surface (eval-harness, verification-loop, ai-regression-testing, security-review).
- **Scope calibration** (lines 20-27): explicit "use only lanes that fit", explicit "do not assume every model has labels, online serving, GPUs" — anti-over-engineering.

---

## 9. Install / uninstall commands

```bash
# Install (target=claude → ~/.claude/)
cd /Users/kobig/Codes/Personals/ECC
npx ecc install --profile minimal --target claude --with capability:machine-learning

# Preview without writing
npx ecc install --profile minimal --target claude --with capability:machine-learning --dry-run

# JSON output for tooling
npx ecc install --profile minimal --target claude --with capability:machine-learning --dry-run --json

# Uninstall (reads install-state.json, reverses)
npx ecc uninstall --target claude

# Verify after install
npx ecc doctor
```

---

## 10. Open follow-ups before actual install

1. **Should `kbg:` namespace survive?** Run `/doctor` after install to see if kbg skills get budget-bumped.
2. **Is there a custom `--modules` set that skips some auto-pulled deps?** E.g., `--modules rules-core,agents-core,commands-core,platform-configs,workflow-quality,machine-learning` would skip `framework-language`/`database`/`devops-infra`/`security` if owner accepts that the MLE skill's "Related Skills" refs will dangle.
3. **`developer` profile** (`manifests/install-profiles.json:33-46`) is the documented "default engineering profile" and includes `framework-language + database + orchestration` — closer match for kbg-shape, but adds `orchestration` module (dmux-workflows + tmux scripts) which we explicitly rejected.
4. **Cache invalidation**: per memory `audit-2026-06-12-spec.md`, after install run `claude plugin update` + restart CC to pick up the new `~/.claude/skills/ecc/` inventory.

---

## Related memory

- [[ecc-everything-claude-code-mine-2026-06-20]] — why kbg rejected ECC's model-as-gate + observer-loop
- [[skill-listing-budget-mechanics]] — desc-load cap mechanics
- [[plugin-cache-stale-trap-trilogy]] — same-version edits no-op → uninstall+trash+reinstall
- [[plugin-install-portability]] — bundled script paths must resolve from any CWD

---

# Part 2 — Version model + shape analysis

## 11. Current version + tagging

| Field | Value |
|---|---|
| `package.json.version` | `2.0.0` |
| `VERSION` (plain text file) | `2.0.0` |
| `agent.yaml` version | `2.0.0` (under `spec_version: 0.1.0`) |
| `.claude-plugin/plugin.json` | `2.0.0` |
| `.claude-plugin/marketplace.json` plugins[0].version | `2.0.0` |
| `.codex-plugin/plugin.json` | `2.0.0` |
| `.agents/plugins/marketplace.json` | `2.0.0` |
| `plugins/ecc/.codex-plugin/plugin.json` | `2.0.0` |
| `.opencode/package.json` | `2.0.0` |

**8 manifests all aligned at `2.0.0`** (verified via `python3` walk on 2026-06-28).

**Git tags in clone**: 0. (clone is shallow; tags were never pushed locally — ECC upstream tag convention is `vX.Y.Z`.)

**CHANGELOG version sections** (`CHANGELOG.md`):

```
## Unreleased
## 2.0.0      - 2026-06-09  (current)
## 2.0.0-rc.1 - 2026-04-28
## 1.10.0     - 2026-04-05
## 1.9.0      - 2026-03-20
## 1.8.0      - 2026-03-04
```

## 12. Version-bump mechanism: `scripts/release.sh`

Single bash script (`scripts/release.sh:1-300`) takes `VERSION` as arg and writes 21 files in one shot:

| File pattern | Bump method |
|---|---|
| `package.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`, `plugins/ecc/.codex-plugin/plugin.json`, `.opencode/package.json` | `sed -i '' 's\|"version": *"[^"]*"\|"version": "X.Y.Z"\|'` (darwin variant) |
| `package-lock.json`, `.opencode/package-lock.json` | inline Node script — patches top-level `version` + `packages[""].version` |
| `VERSION` | `printf '%s\n' > VERSION` |
| `agent.yaml` | regex on `^version:\s*...` |
| `AGENTS.md`, `docs/tr/AGENTS.md`, `docs/zh-CN/AGENTS.md` | `**Version:**` / `**Sürüm:**` / `**版本:**` labels (per-language) |
| `README.md`, `README.zh-CN.md`, `docs/tr/README.md`, `docs/pt-BR/README.md`, `docs/zh-CN/README.md` | both `### vX.Y.Z` heading AND `**Version**` row in cross-platform matrix table |
| `.agents/plugins/marketplace.json` | dedicated Node script (looks up `plugins.find(p => p.name === "ecc")`) |
| `.opencode/plugins/ecc-hooks.ts` | regex on `## Active Plugin: Everything Claude Code vX.Y.Z` banner |
| `docs/SELECTIVE-INSTALL-ARCHITECTURE.md` | regex on `"repoVersion": "..."` example |

**Pre-flight gates** (lines 50-60):
1. Must be on `main` branch
2. Working tree clean (incl. untracked)

**Post-bump gates** (lines 286-291):
1. `node scripts/build-opencode.js` (regenerate `.opencode/dist/`)
2. `node tests/scripts/build-opencode.test.js` (verify build)
3. `node tests/plugin-manifest.test.js` (verify cross-manifest consistency)

**Then** (lines 294-297):
```bash
git add <21 files>
git commit -m "chore: bump plugin version to $VERSION"
git tag "v$VERSION"
git push origin main "v$VERSION"
```

## 13. Semver discipline

- Validates input against `^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$` (line 44)
- **Prerelease tags use `next` npm dist-tag** (line 70 in `release.yml`):
  ```bash
  NPM_DIST_TAG=$(node -p "require('./package.json').version.includes('-') ? 'next' : 'latest'")
  ```
- CI gate (`.github/workflows/release.yml:42-60`): tag must match `vX.Y.Z(-prerelease)?` AND package.json version must equal tag-suffix

## 14. Schema-version surfaces (separate from package version)

These are **content schemas**, not release versions:

| Domain | Schema version constant | File |
|---|---|---|
| Install manifest | `"version": 1` | `manifests/install-{profiles,modules,components}.json` |
| `consult` JSON output | `ecc.consult.v1` | `scripts/consult.js` |
| Observability rubric | `2026-05-11` | `scripts/observability-readiness.js` |
| Operator readiness dashboard | `ecc.operator-readiness-dashboard.v1` | `scripts/operator-readiness-dashboard.js` |
| Release video suite | `ecc.release-video-suite.v1` | `scripts/release-video-suite.js` |
| Harness audit rubric | `2026-05-19` | `scripts/harness-audit.js` |
| Discussion audit | `ecc.discussion-audit.v1` | `scripts/discussion-audit.js` |
| Preview pack smoke | `ecc.preview-pack-smoke.v1` | `scripts/preview-pack-smoke.js` |
| Platform audit | `ecc.platform-audit.v1` | `scripts/platform-audit.js` |
| Release approval gate | `ecc.release-approval-gate.v1` | `scripts/release-approval-gate.js` |
| Control-pane snapshot | `ecc.control-pane.snapshot.v1` | `scripts/lib/control-pane/state.js` |
| MCP inventory | `ecc.mcp.v1` | `scripts/lib/mcp-inventory/canonical-mcp.js` |
| GitHub coordination policy | `ecc.github.coordination.v1` | `scripts/lib/github-coordination/policy.js` |
| Session canonical | `ecc.session.v1` + `ecc.session.recording.v1` | `scripts/lib/session-adapters/canonical-session.js` |
| Skill observation | `ecc.skill-observation.v1` | `scripts/lib/skill-improvement/observations.js` |
| Skill health | `ecc.skill-health.v1` | `scripts/lib/skill-improvement/health.js` |
| Skill amendment proposal | `ecc.skill-amendment-proposal.v1` | `scripts/lib/skill-improvement/amendify.js` |
| Skill evaluation | `ecc.skill-evaluation.v1` | `scripts/lib/skill-improvement/evaluate.js` |

**Two naming conventions**:
- `ecc.<domain>.v<N>` — JSON output schemas (most common)
- `YYYY-MM-DD` — rubric scoring files (calver-style)

## 15. Distribution surfaces

| Channel | Path | Updated by `release.sh` |
|---|---|---|
| npm `ecc-universal` | `package.json` (root) | ✓ |
| Claude Code plugin | `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` | ✓ |
| Codex plugin | `.codex-plugin/plugin.json` + `.agents/plugins/marketplace.json` | ✓ |
| OpenCode plugin | `.opencode/package.json` (compiled to `dist/`) | ✓ (built by `scripts/build-opencode.js`) |
| Cursor / Gemini / Qwen / Zed / Codebuddy / Joycode | `.cursor/`, `.gemini/`, `.qwen/`, `.zed/`, `.codebuddy/`, `.joycode/` configs | ✗ (not in `files:` of root package) |

`.npmignore` excludes: `README.zh-CN.md`, `scripts/release.sh`, `.claude-plugin/PLUGIN_SCHEMA_NOTES.md`, `__pycache__/`, `*.pyc`.

## 16. Versioning philosophy observed

1. **Single source of truth** is `package.json.version` (ECC's release.sh reads from there to compute `OLD_VERSION`)
2. **All public-facing surfaces are bumped in lockstep** — no drift between plugin, marketplace, npm, agent.yaml, README matrix
3. **`Unreleased` is a top-level section** — convention from Keep-a-Changelog, used for in-progress work before the next tag
4. **Pre-release cadence**: `2.0.0-rc.1` (Apr 2026) → `2.0.0` stable (Jun 2026) — 6 weeks between rc and stable
5. **Internal schema versions are independent** — bumped only when JSON shape changes; not tied to plugin release cadence
6. **Cross-platform matrix row in README** keeps `2.0.0` in sync with the actual release — verified by `update_readme_version_row` regex targeting the exact row

## 17. Patterns kbg could borrow (decision pending)

| ECC pattern | kbg equivalent | Verdict |
|---|---|---|
| 8-manifest sync via single script | kbg: 2 manifests (`.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`) | overkill for 2 files |
| `scripts/release.sh` + pre/post gates | kbg has no release script yet (per memory `audit-2026-06-12-spec.md` cache invalidation is manual) | worth adopting for next release |
| `Unreleased` Keep-a-Changelog convention | kbg `CHANGELOG.md` exists but no `Unreleased` header | borrow |
| Semver with `next` dist-tag for prerelease | n/a (kbg not published to npm) | n/a |
| Schema-version constants in lib code | kbg has cage.txt but no schema versioning | not needed at current surface |

## 18. Verified counts in current ECC repo (2026-06-28)

| Surface | Count |
|---|---|
| Skills in `skills/` | 271 (per `find skills -maxdepth 1 -mindepth 1 -type d \| wc -l`) |
| Agents in `agents/` + `.agents/` | 67 (per `.claude-plugin/plugin.json` description) |
| Commands in `commands/` | 92 (legacy + core) |
| Hooks | `hooks/` + `scripts/hooks/` + `scripts/lib/hook-runtime` |
| MCP servers in default config | 1 (`chrome-devtools`, post-June-2026 audit) |
| Locales | 9 (ja, zh-CN, ko-KR, pt-BR, ru, tr, vi-VN, zh-TW, de-DE) |
| Module kinds | rules, agents, commands, hooks, platform, skills, orchestration, docs (8 kinds in `manifests/install-modules.json`) |

These counts match what `package.json` `description` field advertises (`67 agents, 271 skills, 92 legacy command shims`).

## Related memory

- [[ecc-everything-claude-code-mine-2026-06-20]] — kbg rejection of ECC architecture
- [[audit-2026-06-12-spec]] — kbg cache-invalidation manual (vs ECC's release.sh auto-bump)
- [[plugin-install-portability]] — bundled script paths must resolve from any CWD