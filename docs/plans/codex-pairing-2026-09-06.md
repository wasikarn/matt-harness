# Codex pairing plan — Phase 1

Source: `~/Downloads/codex-integration-prompt.md`, run as its own spec (no separate `/to-spec`
pass — decided in the `/grill-with-docs` round that produced this). That round also produced
`CONTEXT.md` (terms: Codex, review gate, pairing) and `docs/adr/0001-gate-codex-setup-not-rescue.md`
(gate `codex:setup`'s review-gate toggle; leave `codex:rescue` ungated). Both are inputs here,
not repeated in full.

Baseline: mh v1.1.4, commit `537027e9`, on this machine's clone.

## A. Install and config

**This machine is already past every step below** — `codex@openai-codex` v1.0.6 is installed,
enabled, and authenticated (`codex-cli 0.153.4`; `codex setup --json` reports `ready: true`,
ChatGPT login active; `reviewGateEnabled: false`). The steps are for a fresh clone/machine:

1. Add the marketplace and install: `/plugin marketplace add openai/codex-plugin-cc`, then
   `/plugin install codex@openai-codex`.
2. `/reload-plugins`, then add `"codex@openai-codex": true` to Claude Code `settings.json`
   (plugins default `defaultEnabled: false`, same as mh — `docs/reference/repo-gotchas.md`).
3. `/codex:setup` — installs the Codex CLI via `npm install -g @openai/codex` if missing,
   reports auth state.
4. `!codex login` (interactive; `--device-auth` or `--with-api-key` if browser login is
   blocked).

**Sandbox/approval recommendation: none needed, and item A's premise doesn't hold for this
plugin.** I verified this in `scripts/codex-companion.mjs` and `scripts/lib/codex.mjs`
(installed v1.0.6), not from docs or memory: every plugin-mediated call already hardcodes its
sandbox per operation —

- `/codex:review`, `/codex:adversarial-review`: `sandbox: "read-only"` (`codex.mjs:1012`,
  the app-server review path).
- `/codex:rescue` / `/codex:transfer`'s task path: `sandbox: request.write ? "workspace-write"
  : "read-only"` (`codex-companion.mjs:491`) — never `danger-full-access`.

This isn't read from `~/.codex/config.toml` at all; the plugin talks to a Codex app-server
directly and passes the sandbox as a structured parameter per call. A `config.toml`
recommendation would only matter for a human running bare `codex`/`codex exec` in a terminal,
outside the plugin — out of scope for "smallest footprint in mh," and the operator's own
business, not the pairing's.

One correction worth recording since I had to verify it rather than assume it: Codex's
`config.toml` schema has since migrated to **permission profiles**
(`default_permissions = ":read-only" | ":workspace" | ":danger-full-access"`, or a custom
`[permissions.<name>]` table) as the documented replacement for the older `sandbox_mode` +
`approval_policy` keys — the two schemes don't compose. The `-s/--sandbox` CLI flag on
`codex exec` still accepts the legacy three values (`read-only`, `workspace-write`,
`danger-full-access`; confirmed against `codex exec --help`, v0.153.4) — that's the flag
vocabulary the plugin itself uses internally. Irrelevant to this plan's own recommendation
above, but a live discrepancy from what item A's own wording assumed, so it's the kind of
thing that would have shipped wrong if I'd written from memory.

Review gate: off by default (`stopReviewGate` config key, per-workspace). Detail in item E.

## B. Routing

| skill | invocation | mh touchpoint / fallback | reverse handoff |
|---|---|---|---|
| `/codex:review` | user or model | read-only diff review; Claude-side alternative: `mattpocock-skills:code-review`. Fallback on rate-limit/absence: run the Claude-side review instead, invoked by the operator — independence lost for that pass |
| `/codex:adversarial-review` | user or model | challenges a plan after `mattpocock-skills:grilling`; Claude-side alternative: `mh:plan-reviewer`. Same fallback shape as review |
| `/codex:rescue` | **user or model** — no `disable-model-invocation`, and `codex:codex-rescue` is a full Agent-tool `subagent_type` | writes files through Codex, not Claude Code tools — item C's gate gap. Gated at the review-gate-toggle level only (ADR-0001); the dispatch itself is not gated (ADR-0001, deferred) |
| `/codex:setup` | **user or model** — no `disable-model-invocation` | the one surface mh puts a real gate on: `ask`-tier PreToolUse, matcher `Skill`, firing on `tool_input.skill == "codex:setup"` with `--enable-review-gate` in `tool_input.args` (new; see item E's neighbor, the gate itself, not check 71) |
| `/codex:transfer` | user only (`disable-model-invocation: true`) | Claude near its limit → hands the session to a resumable Codex thread. Reverse of the fallback direction |
| `/codex:status` | user only | job/review-gate status, read-only |

The bolded rows are the actual finding of this plan: the document's own item B asked for this
column, and two of eight commands (`setup`, `rescue`) don't carry `disable-model-invocation:
true` in their frontmatter (checked directly against v1.0.6's `commands/*.md`). Constraints 1
and 2 are prose against that gap; ADR-0001 records which half of the gap mh closes with a real
gate and which it accepts as documented only.

## C. Gate gap

`/codex:rescue` edits files through the Codex app-server, not through Claude Code's own
tool-call pipeline — none of mh's five gates (`gate:bash:irrecoverable`,
`gate:bash:subagent-git-guard`, `gate:task:complete-separation`, `gate:write:test-integrity`,
`gate:write:config-guard`) see those writes. This repo's own git hooks (`git-hooks/pre-commit`,
`pre-push`) are the vendor-agnostic floor: whatever wrote a file, the same gauntlet and audit
run before it ships. See `CONTEXT.md`'s "review gate" entry for how this differs from Codex's
own Stop-time review gate, and ADR-0001 for why `rescue`'s dispatch itself stays ungated for
now rather than picking up a novel Agent-tool gate as a rider on this trial.

## D. AGENTS.md

Codex reads `AGENTS.md`, not `CLAUDE.md`. Smallest pointer, one paragraph, documented in
`docs/reference/codex-integration-map.md` (not README — see item H for the 120-line-cap
check):

> This repo runs under `mh@wasikarn` (Claude Code). Its full doctrine is `CLAUDE.md` +
> `docs/METHODOLOGY.md`; the parts that bind you too: (1) the decision-sizing triad before any
> non-trivial change — one-way door? blast radius? riskiest assumption? — (2) a requirement is
> a claim to test, not a truth to obey: name what's ambiguous, missing, or assumed before
> touching code, (3) a bug fix starts with a failing test, the test passing is done. mh's
> `gate:*` PreToolUse hooks are Claude Code hooks — you are not under them; this repo's git
> hooks (`git-hooks/pre-commit`, `pre-push`) are the floor that applies to every edit
> regardless of which agent made it.

No generator, no sync script: this paragraph is short enough to hand-keep in sync with
`CLAUDE.md`'s own map on the rare occasion the doctrine numbering shifts.

## E. harness-audit check 71

WARN if Codex's Stop-time review gate is on for this repo; INFO otherwise (installed/enabled
state), matching check 70's numbering note — 70 is taken (shipped 2026-09-06, v1.1.4), 71 is
next and free.

**Detection: a local file read, not a shell-out.** Verified directly in v1.0.6's
`scripts/lib/state.mjs`, not guessed:

- State lives at `$CLAUDE_PLUGIN_DATA/state/<slug>-<hash>/state.json`, where `slug` is the
  repo root's basename sanitized to `[a-zA-Z0-9._-]` (falling back to `"workspace"` if that
  empties it) and `hash` is the first 16 hex chars of `sha256(realpath(repo_root))`.
  `resolveWorkspaceRoot` = the git repo root (`ensureGitRepository`), same value `$REPO_ROOT`
  in `audit.sh` already resolves.
- `$CLAUDE_PLUGIN_DATA` is Claude Code's own per-plugin data directory
  (`~/.claude/plugins/data/<plugin>-<marketplace>/` — observed consistent across all 16
  installed plugins on this machine, e.g. `mh-wasikarn`, `codex-openai-codex`; not documented
  in `docs/reference/env-vars.md` because mh doesn't use it itself, but real). The env var
  isn't set when `audit.sh` runs as a bare `bash` invocation (only when Claude Code itself
  spawns a hook), so check 71 computes the path directly —
  `$HOME/.claude/plugins/data/codex-openai-codex/state/<slug>-<hash>/state.json` — rather than
  depending on the env var.
- Rejected: shelling out to `codex-companion.mjs setup --json` (which reports
  `reviewGateEnabled` directly, no reverse-engineering needed). None of the 27 existing check
  fragments spawn a subprocess beyond coreutils; this would spawn node, the Codex CLI, and an
  auth check inside a script meant to run fast and local before a commit. The local-file-read
  approach's failure mode (file missing, unparseable, or the slug/hash scheme drifts in a
  future Codex version) is exactly Option C's fallback — INFO, not a wrong WARN — so it costs
  nothing extra to prefer over the shell-out.

**Known limitation, stated up front rather than discovered later:** this assumes the plugin
installs under marketplace alias `openai-codex` (matching this document's own naming and the
one used on this machine). A different marketplace alias changes the plugin-data directory
name; check 71 would then silently report "not installed" — fail-open, not a false CRIT,
consistent with every other WARN-tier check here.

Needs (per the document's own item E): the number added to `_exp_ids` in `audit.sh`;
known-bad (`stopReviewGate: true` in a fixture state.json) and known-good (absent/false)
fixtures under `tests/skills/harness-audit/known-bad/`, each with an `agents/foo.md`;
`expect_warn`/`expect_silent` lines in `test-harness-audit.sh`. Fixture state files can't
reproduce the real hashed path (it's derived from the real repo's location), so the check
itself needs a root-override hook the same shape as every other check's `$REPO_ROOT`
parameter, with the fixture's `state.json` placed at a path the check computes from *that*
fake root — Phase 2 detail, not a Phase 1 fork.

## F. cost-report

**Feasible, and Codex invocations are visible today** — every `/codex:*` call is either a
`Skill` tool_use (`tool_input.skill` starting `"codex:"`) or, for `codex:codex-rescue`, an
`Agent` tool_use (`tool_input.subagent_type` starting `"codex:"`) in the Claude transcript
JSONL `hooks/stop/cost-tracker.sh` already reads. This is a **count**, not a cost — Codex
exposes no local per-call price — and it's a separate tally from `emit_rows`'s token
aggregation (that function only scans `.message.usage` on `claude*`-model assistant turns;
Codex tool_use blocks live inside those same Claude turns but need their own pass).

Roughly 12–15 lines, not quite the prompt's "under ~10": a new function scanning the same
transcript file list already passed to `emit_rows`, tallying `tool_use` blocks matching
`.name == "Skill" and (.input.skill // "" | startswith("codex:"))` or `.name == "Agent" and
(.input.subagent_type // "" | startswith("codex:"))`, grouped by the matched name, emitted as
one small object (e.g. `{"codex:review": 2, "codex:rescue": 1}`) alongside the existing
per-session row. Pinned by one new case in `tests/hooks/test-session-stop.sh` (a fixture
transcript with a `Skill` tool_use for `codex:review` — the existing fixture style, not a new
harness). `scripts/workflows/cost-report-dedup.js` gets one new `=== Codex invocations ===`
section, summed across sessions, no `$`.

## G. Trial and kill criterion

Unchanged from the source document — two weeks, in order: (1) Claude tokens/pass vs. the
`mh:cost-report` baseline taken before Phase 2 ships; (2) findings per Codex review not raised
by the Claude-side review, tallied by the operator; (3) Codex limit hits and fallbacks/week;
(4) wall-clock added per pass. Rollback: `claude plugin disable codex@openai-codex`, mh
unchanged.

## H. Files touched

Expected, Phase 2:

- `README.md` — optional-tool row + pairing note (must stay under 120 lines; currently 103,
  so about 17 lines of headroom for Phase 2 to spend).
- `docs/reference/codex-integration-map.md` — new, item B's table + AGENTS.md pointer (item D).
- `CLAUDE.md` — one line in composer-not-creator order (check the installed codex plugin
  before creating a new mh surface).
- `docs/reference/composer-not-creator.md` — matching line.
- `hooks/hooks.json` + a new `hooks/gates/codex-setup-guard.sh` — the ask-gate from ADR-0001.
- `skills/meta/harness-audit/scripts/checks/71-codex-review-gate-state.sh` + `_exp_ids` in
  `audit.sh` + known-bad/known-good fixtures + `test-harness-audit.sh` lines.
- `hooks/stop/cost-tracker.sh` + `scripts/workflows/cost-report-dedup.js` + a case in
  `tests/hooks/test-session-stop.sh` (item F).
- `CHANGELOG.md` entry; both manifests bumped (1.1.4 → 1.1.5 — re-read both immediately before
  Phase 2's commit, per `docs/reference/branching-model.md`, in case a peer session moved
  first).

Already produced by the grilling round, not Phase 2 output: `CONTEXT.md`,
`docs/adr/0001-gate-codex-setup-not-rescue.md`, this file.

Nothing beyond this list — nine files plus fixtures, matching constraint 3's "smallest
footprint" once the setup-gate script and the check are counted as the two genuinely new
pieces of mh code this pairing requires.

## Open questions

1. **`hooks/hooks.json` matcher `"Skill"` has no precedent anywhere on this machine** — not
   in mh, not in any of the other 15 installed plugins. I'm confident it fires (Claude Code's
   PreToolUse dispatch is generic over `tool_name`, and every gate here already reads
   `tool_name`/`tool_input` off the same stdin JSON shape a `Skill` call would produce), but
   it's unverified in this specific plugin until Phase 2 writes it and the gate canary
   (`scripts/gate-canary.sh`) runs against it.
2. **Whether a user-typed `/codex:setup --enable-review-gate` also fires the new ask-gate.**
   Likely yes (nothing in this transcript's own evidence distinguishes a user-typed slash
   command from a model-invoked `Skill` call at the tool-call layer for a skill *without*
   `disable-model-invocation`), and `ask`-tier makes that fine either way — it costs the
   operator one confirmation on their own deliberate action, same as `gate:write:config-guard`
   already does for settings.json edits. Not reproducible without actually typing it in a live
   session.
3. **Item F's cost-tracker change is closer to 15 lines than the document's guessed 10.** Not
   blocking — flagged so Phase 2 doesn't force-fit a smaller diff than the logic needs.
