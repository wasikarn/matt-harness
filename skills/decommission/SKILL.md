---
name: decommission
description: "Assert and sign the complete absence of deprecated code, jobs, daemons, or symlinks so nothing keeps running in the dark. Use when retiring systems, deleting workers, removing launchd/cron jobs, or cleaning legacy hooks. Thai: 'decommission', 'ลบให้หมด', 'witness ว่าหายไป'. Don't use for new features, presence checks (use kbg:assert-presence), or when you cannot verify absence across environments."
---

# Decommission

Most "deletions" are partial. Code path goes away but the cron still fires, the launchd job still respawns the daemon, the symlink in `~/.claude/hooks/` still points at a deleted file. Tests don't catch it because nothing is checking for *absence*. This skill makes absence a first-class asserted state, signed with ed25519 so the assertion is tamper-evident.

**Rationale**: Past incident — a worker script was deleted in commit `c3e9b50` but the daemon kept running for weeks, logging 150K silent failures before anyone noticed. A signed `ABSENT_*` witness would have failed the next CI run.

## Install (one-time)

This skill is delivered via the `kbg@kobig` plugin. No manual symlink needed.

```bash
/plugin install kbg@kobig
```

If you need the standalone script outside a Claude Code session, run from the repo clone:

```bash
# from repo root:
bash ${CLAUDE_SKILL_DIR}/scripts/witness.sh sign --namespace=decommission <slug>
bash ${CLAUDE_SKILL_DIR}/scripts/witness.sh verify --namespace=decommission
```

Three states with distinct lifetimes:

| State | Where | Lifetime |
|---|---|---|
| Keypair | `~/.ssh/witness_ed25519` | per-user, one for all repos |
| Allowed signers | `<repo>/.witness/allowed_signers` | per-repo, git-tracked |
| Witnesses + signatures | `<repo>/.witness/<slug>.{txt,sig}` | per-repo, git-tracked |

## Quick start

From inside any project's repo root — no setup step required, sign auto-inits the keypair + `.witness/allowed_signers` on first use.

**Standalone** (from repo root):
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/witness.sh sign --namespace=decommission <slug>
bash ${CLAUDE_SKILL_DIR}/scripts/witness.sh verify --namespace=decommission
```

`witness.sh sign` opens `$EDITOR` on `.witness/<slug>.txt`. Fill in assertions, save, exit — script signs and writes `.witness/<slug>.txt.sig`. Commit both files.

`witness.sh verify` exits `2` and prints `DECOMMISSION DRIFT` if any orphan resurfaced.

If you prefer to seed the keypair + signers file explicitly (e.g. to commit `.witness/allowed_signers` before signing anything yet), run `witness.sh init --namespace=decommission`. It's idempotent and what `witness.sh sign` calls under the hood.

## Assertion grammar

Each non-comment line in `.witness/<slug>.txt` is one assertion. `~` expands to `$HOME`.

| Directive | Checks that... |
|---|---|
| `ABSENT_PATH: <path>` | file/dir/symlink does not exist |
| `ABSENT_CRON_MATCH: <pattern>` | `crontab -l` contains no line with this substring |
| `ABSENT_LAUNCHD: <label>` | `launchctl list` contains no job with this label (macOS) |
| `ABSENT_PROCESS_MATCH: <pattern>` | `pgrep -lf` finds no matching process |

Required header comments — verify enforces presence:

```
# decommission witness: <slug>
# decommissioned: <ISO-8601 UTC>
# reason: <one line why>
# rollback: <how to restore if needed>
```

See `REFERENCE.md` for edge cases (TOCTOU, path expansion, false positives) and verify-gate wiring (pre-commit, CI, scheduled). See `EXAMPLES.md` for worked scenarios.

## Workflow

1. **Plan the decommission** — list every artifact the component creates: scripts, hooks, crons, launchd plists, log dirs, sockets.
2. **AskUserQuestion** single-select: "Decommission plan: [N] artifacts identified ([list]). Removal is permanent. Proceed?"
   - `Proceed with removal (Recommended when the inventory is complete and the user accepts permanent deletion)` — continue
   - `Revise plan (Recommended when an artifact is missing or the user wants to keep something)` — stop and revisit step 1
3. **Remove the artifacts** — `git rm`, `crontab -e`, `launchctl bootout`, etc. Commit.
4. **Run `witness.sh sign --namespace=decommission <slug>`** — author the negative-assertion manifest.
5. **Run `witness.sh verify --namespace=decommission` once locally** — confirms the deletion was complete *now*.
6. **Commit `.witness/<slug>.txt` and `.witness/<slug>.txt.sig`**.
7. **Wire `witness.sh verify --namespace=decommission` into CI or SessionStart hook** — fails future sessions if orphans return.

## Anti-patterns

- **Witness for things still in use** — this is decommission-only. If the asset should exist, write a test, not a witness.
- **Rotting witnesses** — if a component is intentionally re-introduced, `git rm` the witness file in the same commit. Don't comment it out.
- **Skipping the `rollback:` line** — without rollback notes, you'll forget how to restore six months later.
- **Witness without verify gate** — sign-and-forget is theatre. The skill's value is in the gate.

**Named model** (cc-thinking-skills): asserting *absence* as a first-class state is *via-negativa* (improve by removal, then prove the removal stuck). Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
