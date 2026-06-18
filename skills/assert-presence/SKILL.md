---
name: assert-presence
description: "assert-presence"
disable-model-invocation: true
disable-model-invocation-reason: "machinery primitive (also user-invocable: false) — invoked by hooks/CI, not by user or model"
user-invocable: false
---

# Assert Presence

Agents say "I fixed it" — but two sessions later, after a revert, refactor, or merge conflict, that fix may be gone and nobody noticed. This skill encodes the agent's claim as a signed assertion: marker substring + file path + ed25519 signature. Verify gate runs in pre-commit / CI / next session and fails loud if the claim regressed.

Same crypto as [[decommission]] but inverted semantics:
- decommission asserts `ABSENT_*` (it must NOT exist)
- assert-presence asserts `PRESENT_*` (it must EXIST)

Shared keypair (`~/.ssh/witness_ed25519`), separate ssh-keygen namespace (`assert-presence`), separate manifest naming (`.witness/assert-presence-<slug>.txt`).

## Install (one-time)

This skill is delivered via the `kbg@kobig` plugin. No manual symlink needed.

```bash
/plugin install kbg@kobig
```

If you need the standalone script outside a Claude Code session, run from the repo clone:

```bash
# from repo root:
bash skills/decommission/scripts/witness.sh sign --namespace=assert-presence <slug>
bash skills/decommission/scripts/witness.sh verify --namespace=assert-presence
```

## Quick start

From inside any project's repo root — no setup step required, sign auto-inits the keypair + `.witness/allowed_signers` on first use:

```bash
# when an agent reports a concrete change worth pinning:
bash ${CLAUDE_SKILL_DIR}/../decommission/scripts/witness.sh sign --namespace=assert-presence <slug>

# verify (run in CI, pre-commit, or scheduled cron):
bash ${CLAUDE_SKILL_DIR}/../decommission/scripts/witness.sh verify --namespace=assert-presence
```

`witness.sh sign` opens `$EDITOR` on `.witness/assert-presence-<slug>.txt`. Fill in assertions, save, exit — script signs and writes `.sig`.

`witness.sh verify` exits `2` and prints `ASSERTION REGRESSION` if any asserted marker is missing.

If you prefer to seed the keypair + signers file explicitly, run `witness.sh init --namespace=assert-presence`. Idempotent — generates `~/.ssh/witness_ed25519` if missing (shared with [[decommission]] when both are used), then writes/extends `.witness/allowed_signers` to authorize the `assert-presence` namespace.

## Assertion grammar

| Directive | Checks that... |
|---|---|
| `PRESENT_FILE: <path>` | file exists at path |
| `PRESENT_MARKER: <path> :: <substring>` | file exists AND contains the substring |

Path expansion: `~` → `$HOME`. Separator for `PRESENT_MARKER` is ` :: ` (space-colon-colon-space) — unlikely to appear in code or paths.

Required header comments:

```
# assert-presence witness: <slug>
# asserted: <ISO-8601 UTC>
# agent: <who/what asserted it — agent name, or "human", or PR number>
# evidence: <what success looks like — passing test, fixed file:line, working command>
```

## Anti-patterns

- **Asserting on aspirational state** — sign AFTER the work lands and verify passes locally once. Sign-before-doing = ceremony.
- **Hashing whole files** — refactor renames a variable and your assertion breaks. Use `PRESENT_MARKER` substring (resilient) not full file sha256 (brittle).
- **Substring too generic** — `PRESENT_MARKER: src/auth.ts :: throw` will match anything. Anchor with a unique fix-id comment: `// FIX-auth-null` or similar.
- **Assertion without expiry plan** — if a fix is intentionally refactored later, `git rm` the assertion file in the same commit. Don't leave stale assertions to drift.

## Workflow

1. **Agent completes a change** — verify it works locally (test passes, file edited, command runs)
2. **Pick a marker that anchors the change** — a fix-id comment, a function signature, a unique variable name
3. **Run `witness.sh sign --namespace=assert-presence <slug>`** — fill in `PRESENT_MARKER` / `PRESENT_FILE` assertions + headers
4. **Run `witness.sh verify --namespace=assert-presence` locally** — confirm marker is present *now*
5. **Commit `.witness/assert-presence-<slug>.{txt,sig}`** alongside the change
6. **Wire `witness.sh verify --namespace=assert-presence` into pre-commit / CI** (same gate as decommission — they coexist)
