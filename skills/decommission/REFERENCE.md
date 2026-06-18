# Decommission — Reference

## Manifest format (full)

```
# decommission witness: indexer-worker
# decommissioned: 2026-01-15T18:30:00Z
# reason: replaced by inline indexing in cli (commit abc1234)
# rollback: git revert abc1234 && bash bootstrap.sh

ABSENT_PATH: ~/repo/scripts/indexer-worker.sh
ABSENT_PATH: ~/.claude/hooks/indexer-trigger.sh
ABSENT_CRON_MATCH: indexer-worker
ABSENT_LAUNCHD: com.example.indexer
ABSENT_PROCESS_MATCH: indexer-worker
```

## Why ssh-keygen + ed25519

- macOS ships `ssh-keygen` natively — no Homebrew, no `cosign`, no `minisign` to install
- `ssh-keygen -Y sign` / `-Y verify` use the SSH allowed-signers format also used by `git config gpg.format ssh` — reuses the same keypair if you already sign commits
- ed25519 produces 88-char signatures; manifests stay diffable

## allowed_signers format

```
alice namespaces="decommission" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...comment
```

- First field: signer identity (passed to `-I` on verify)
- `namespaces="decommission"` scopes the key — a key valid for `decommission` will not validate a witness signed under a different namespace (e.g. `git`)
- Multiple signers: one line each. Verify accepts any line that matches `-I`.

## Verify exit codes

| Code | Meaning |
|---|---|
| `0` | All witnesses present and all assertions hold |
| `2` | At least one orphan detected OR a signature is invalid OR a witness is missing a required header |
| `1` | Tooling error (missing `ssh-keygen`, missing `.witness/allowed_signers`, etc.) |

CI/hook callers should treat `2` as `block`, `1` as `fail open with warning` (don't lock yourself out if the keypair is missing on a fresh clone).

## Edge cases

### TOCTOU
Verify is point-in-time. A daemon that starts *after* `witness.sh verify` finishes still escapes. Mitigations:

- Run verify in SessionStart hook (catches drift between sessions)
- Run in scheduled CI (catches drift in the dark hours)
- For high-stakes components, add `ABSENT_LAUNCHD:` not `ABSENT_PROCESS_MATCH:` — kills the respawner, not the symptom

### Path expansion
Only `~` is expanded to `$HOME`. Environment variables (`$XDG_CONFIG_HOME`, etc.) are not expanded — they'd make assertions machine-dependent. Use absolute paths when possible.

### False positives on `ABSENT_PROCESS_MATCH`
`pgrep -lf` matches the full command line. `ABSENT_PROCESS_MATCH: indexer` will match `vim claude/skills/indexer/SKILL.md` while you're editing. Prefer specific patterns: `ABSENT_PROCESS_MATCH: /usr/local/bin/my-worker`.

### Cron matching
`ABSENT_CRON_MATCH` substring-matches against `crontab -l` lines. It does NOT match user-other-than-current crontabs, system crontabs in `/etc/cron.d/`, or anacron. If decommissioning a system cron, add `ABSENT_PATH: /etc/cron.d/<file>` instead.

### Witness for something temporarily disabled
Don't. Witnesses assert *permanent* absence. If you're A/B-testing a removal, use a feature flag and bring back the witness only when the removal sticks.

## Keypair rotation

If `~/.ssh/witness_ed25519` is lost or compromised:

1. Generate new key: `bash ${CLAUDE_SKILL_DIR}/scripts/witness.sh init --namespace=decommission --force`
2. Append the new pubkey to `.witness/allowed_signers` (don't remove the old line yet)
3. Re-sign every witness: `for f in .witness/*.txt; do ssh-keygen -Y sign -f ~/.ssh/witness_ed25519 -n decommission "$f"; done`
4. Commit, verify, then remove the old pubkey line
5. Old `.sig` files are now invalid — verify will refuse them on the next run, forcing the re-sign

## Why not use `git log` / `pre-commit` for this?

`git log` proves *something was removed in commit X*. It does not prove *it stays removed*. A future commit can re-add the file (intentionally or via revert) without anyone noticing. Witness verify checks current filesystem state every run — it's the missing inverse of a test.

## Verify gate wiring

The skill ships scripts only — wiring the verify gate is per-repo. Recommended layers, in order of catch-rate:

### 1. Git pre-commit (recommended baseline)

`.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
if [ -d .witness ]; then
  bash ${CLAUDE_SKILL_DIR}/scripts/witness.sh verify --namespace=decommission || exit 1
fi
```

Bypassable with `--no-verify` (escape hatch for emergencies). Catches drift before it enters git history.

### 2. CI workflow (catches `--no-verify` bypass)

`.github/workflows/decommission-verify.yml`:

```yaml
name: decommission-verify
on: [push, pull_request]
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          if [ -d .witness ]; then
            bash ${CLAUDE_SKILL_DIR}/scripts/witness.sh verify --namespace=decommission
          fi
```

Caveats: `ABSENT_LAUNCHD` will always pass on Linux CI (no `launchctl`), `ABSENT_PROCESS_MATCH` only sees the CI container. Use CI for the assertion types that travel (path + cron-pattern); use local pre-commit + scheduled job for the host-bound ones.

### 3. Scheduled local verify (catches host-specific drift)

For `ABSENT_LAUNCHD` and `ABSENT_PROCESS_MATCH`, only the host running the daemon can see the orphan. Run periodically via cron or launchd itself:

```cron
0 9 * * 1  cd ~/repo && bash ${CLAUDE_SKILL_DIR}/scripts/witness.sh verify --namespace=decommission | logger -t decommission-verify
```

Weekly Monday-morning catch with output to syslog. Don't try to make this block anything — just surface drift.

### What NOT to wire it to

- **Claude Code `SessionStart` hook globally** — fires in every cwd, including repos that have no `.witness/`. Latency + cognitive cost outweighs benefit.
- **`pre-push`** — too late, the bad state is already in local commits. Use `pre-commit`.
- **`post-commit`** — runs after the bad state is recorded. Detection without prevention.
