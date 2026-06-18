# Decommission — Worked Examples

## Scenario A: Background worker with multi-layer consumers

A common shape: one script gets installed in **three layers** simultaneously, so deleting just the source file leaves orphan triggers behind.

```
src/             — the worker itself           (layer 1)
launchd/cron     — the respawner               (layer 2)
hooks/symlinks   — N callers across N repos    (layer 3)
```

If you only `git rm` layer 1, layers 2 and 3 keep firing and either (a) silently fail and spam a log nobody tails, or (b) silently fall through to a no-op and degrade behavior nobody notices.

### Naive decommission (what goes wrong)

```bash
git rm src/indexer-worker.py
git commit -m "remove legacy indexer"
```

Aftermath:
- launchd job `com.you.indexer` keeps respawning, exits non-zero, retries forever
- Job's stderr piped to `~/.cache/indexer/err.log` which nobody reads
- Six downstream repos still have `.git/hooks/post-merge -> ../../../shared/indexer-trigger.sh` symlinks pointing into the void
- Failures accumulate for days/weeks before anyone notices a downstream symptom (drifted index, broken search, stale embeddings)

### Decommission with witness

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/witness.sh sign --namespace=decommission indexer-worker
```

Editor opens — fill in:

```
# decommission witness: indexer-worker
# decommissioned: 2026-05-22T18:30:00Z
# reason: replaced by inline indexing in cli (commit abc1234)
# rollback: git revert abc1234 && bash bootstrap.sh

# Layer 1 — source
ABSENT_PATH: ~/repo/src/indexer-worker.py
ABSENT_PATH: ~/repo/scripts/indexer-fswatch.sh

# Layer 2 — respawner
ABSENT_LAUNCHD: com.you.indexer
ABSENT_PATH: ~/Library/LaunchAgents/com.you.indexer.plist

# Layer 3 — consumers (symlinks across collection repos)
ABSENT_PATH: ~/repos/project-a/.git/hooks/post-merge
ABSENT_PATH: ~/repos/project-b/.git/hooks/post-merge
ABSENT_PATH: ~/repos/project-c/.git/hooks/post-merge
```

Save, exit. Script runs `ssh-keygen -Y sign` → produces `.witness/indexer-worker.txt.sig`.

Then:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/witness.sh verify --namespace=decommission
```

**On day 0** (decommission day): verify fails immediately because launchd is still loaded and the symlinks still exist. Forces you to actually clean up all three layers:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.you.indexer.plist
rm ~/Library/LaunchAgents/com.you.indexer.plist
for r in ~/repos/project-{a,b,c}; do rm "$r/.git/hooks/post-merge"; done
```

Verify again — now passes. Commit the witness + signature.

**On day 30**: a teammate runs `git revert abc1234` to roll back the change. The source file comes back. CI runs `witness.sh verify --namespace=decommission` → exits 2 with `ORPHAN PATH: ~/repo/src/indexer-worker.py still exists` → blocks the merge until someone consciously decides to either (a) finish the revert by also `git rm`ing the witness, or (b) keep the witness and remove the file. Either way it's a decision, not a silent regression.

## Scenario B: Lightweight 2-layer (cron + helper)

Not every component is multi-layer. Sometimes you just have:

```
scripts/log-rotator.sh
crontab: 0 3 * * * ~/scripts/log-rotator.sh
```

Witness stays small:

```
# decommission witness: log-rotator
# decommissioned: 2026-04-10T00:00:00Z
# reason: superseded by logrotate config
# rollback: restore scripts/log-rotator.sh and re-add cron entry

ABSENT_PATH: ~/scripts/log-rotator.sh
ABSENT_CRON_MATCH: log-rotator.sh
```

Two assertions, one signature. The skill scales down — you don't pay for layers you don't have.

## Scenario C: Claude Code hook decommission

Hooks have their own 3-layer install pattern (per `feedback_hook_install_symlinks`): the script, the `settings.json` entry, the symlink into `~/.claude/hooks/`. Decommissioning a hook needs all three layers asserted:

```
# decommission witness: prompt-logger-hook
# decommissioned: 2026-05-22T00:00:00Z
# reason: replaced by Claude Code native transcript export
# rollback: git revert <commit>

ABSENT_PATH: ~/dotfiles/claude/hooks/prompt-logger.sh
ABSENT_PATH: ~/.claude/hooks/prompt-logger.sh

# settings.json — verify by absence of substring (no JSON parser dep)
# This catches the case where the symlink + script were removed but the
# settings.json entry was forgotten, which would log "hook not found" errors.
```

Note: there's no `ABSENT_JSON_KEY` directive in v1 grammar. For settings.json, either:
- Add a custom `ABSENT_PATH` to a file you control that mirrors the setting, OR
- Use `ABSENT_PROCESS_MATCH: prompt-logger` to catch the running symptom

(Adding a JSON-aware assertion type is a deliberate v2 decision — see `REFERENCE.md` on assertion grammar evolution.)

## What these scenarios share

1. **The verb is "assert absence", not "delete"** — you delete with normal tooling (`git rm`, `launchctl bootout`, `rm symlink`). Witness encodes the *invariant* that the deletion stays done.
2. **The cost is paid at decommission time, not later** — verify forces you to finish the job that day, before the orphan can spin for weeks.
3. **The signature gates rollback semantics** — if someone reverts the deletion, they either revert the witness too (intentional restore) or the gate fails (catches accidental restore).
