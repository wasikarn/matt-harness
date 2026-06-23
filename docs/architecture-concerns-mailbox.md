# Architecture Concerns — Mailbox System

## 1. Atomicity / Race Conditions on macOS (send.sh)

`mailbox-send.sh` attempts atomic delivery via `mv`. On GNU/Linux `--no-clobber` guards against overwrites, but the macOS fallback uses a non-atomic test-then-mv sequence:

```bash
if [ -e "$DEST_DIR/..." ]; then ...; fi
mv "$tmpfile" "$DEST_DIR/"
```

A second sender racing between the test and the `mv` could overwrite the first message silently. In practice `msg_id` contains a UUID suffix so collision probability is low, but the macOS path weakens the atomicity contract. If this system ever runs on a shared filesystem (NFS, SMB), `mv` atomicity itself is not guaranteed.

**Mitigation:** Use `ln` + `mv` for atomic swap, or add a filesystem lock (`flock`) around the move on both platforms.

## 2. Linear Scan Performance (poll.sh, reap.sh)

`mailbox-poll.sh` performs a linear scan of all `*.md` files in `inbox/<agent>/unread/` and `broadcast/unread/`, parsing YAML frontmatter per file with `sed`/`grep`. `mailbox-reap.sh` walks every agent subdirectory. For a small team (tens of agents, hundreds of messages) this is fine, but the complexity is O(N*M) where N = agents and M = messages per agent.

There is no index, no sharding by date, and no caching. If an agent is offline for days and accumulates thousands of unread messages, poll latency grows linearly. Reap on a large fleet could become a periodic CPU spike.

**Mitigation:** If scale grows beyond ~1,000 messages per agent, introduce a lightweight index (e.g., a JSON summary file per inbox that `send.sh` appends to atomically) so `poll.sh` can read O(1) metadata instead of parsing every file.

## 3. No Idempotency / Duplicate-Read Guard for Direct Messages

`mailbox-read.sh` is idempotent for broadcasts (`touch` a read-receipt) but not for direct messages: moving `unread/{id}.md` to `read/{id}.md` fails loudly on the second call because the source no longer exists. Callers that retry on transient errors (e.g., a subshell fork failure) will get a hard error rather than a no-op.

**Mitigation:** Add an early-exit path in `read.sh` — if the message already exists in `read/`, return 0 and log a `message_already_read` event rather than failing.

## 4. Observability Gap

The system logs governance events (`journal_append`) but emits no operational metrics: no message queue depth per agent, no time-since-last-poll per agent, no reap volume trends. A stuck agent (never polling) or a runaway broadcaster (flooding messages) is invisible without manual filesystem inspection.

**Mitigation:** Add a lightweight `mailbox-status.sh` script that emits JSON with counts per agent (unread/read/archive/broadcast pending) for external monitoring to scrape.

---

# Architecture Concerns — Atomic Locking System

## 1. Zombie lock directories (no lock.json) require periodic reaping

**Concern:** `lock-claim.sh` will never steal a directory that lacks a `lock.json`, even if the directory is months old. This is the correct trade-off for atomicity — a missing `lock.json` means another claimer is mid-flight — but it leaves a hole for crashed claimers. `lock-reap.sh` closes this hole by treating missing `lock.json` as epoch-0 stale, yet reaping is manual / cron-only today.

**Production impact:** If the reaper is not run on a cadence (e.g., every 5 min), a single crashed agent can pin a resource forever. The harness has no built-in reap trigger.

**Recommendation:** Add a `trap EXIT` inside `lock-claim.sh` that cleans up the directory if the script exits before `mv` completes. This reduces the zombie window from "infinite" to "one agent lifetime". Keep the reaper as a backstop.

---

## 2. Governance-event loss is silent

**Concern:** Every script wraps `journal_append` with `> /dev/null 2>&1 || true`. If `_lib.sh` is present but `journal_append` exits non-zero (jq missing, journal disk full, redaction failure), the event is dropped with no trace.

**Production impact:** Audit/compliance regressions go unnoticed. The very feature designed to provide evidence trails becomes unreliable under stress.

**Recommendation:** Remove the `|| true` swallow. Instead, let `journal_append` failures surface on stderr and, if the script's primary operation already succeeded, continue with the primary operation but emit a `WARN` to stderr so log aggregation catches it. Never drop silently.

---

## 3. `mkdir` atomicity is filesystem-local

**Concern:** The atomic-claim guarantee rests on POSIX `mkdir` being atomic. This holds for local APFS/EXT4/XFS and for modern NFSv4 with proper configuration, but it is NOT guaranteed on all network filesystems (e.g., older NFSv3, some FUSE mounts, or distributed cloud storage posing as POSIX).

**Production impact:** If `~/.claude/locks` is ever moved to a shared network mount (e.g., for multi-host agent fleets), two agents on different hosts could both observe `mkdir` success and write conflicting `lock.json` files.

**Recommendation:** Document the POSIX-filesystem requirement in the deployment notes. If multi-host locking becomes a requirement, migrate to a real coordination service (SQLite with WAL and `BEGIN IMMEDIATE`, Redis `SET NX`, or a simple file-based `flock` fallback) rather than relying on directory creation alone.

---

## 4. Resource-ID encoding collision risk

**Concern:** File-path encoding replaces `/` with `--`. A task named `api--users.py` and a file `api/users.py` both encode to `file--api--users.py`, producing a collision. The current implementation does not percent-encode or hash the resource ID.

**Production impact:** Low today because resource IDs are human-curated, but an automated pipeline could mint colliding IDs.

**Recommendation:** If collision surface grows, switch to a deterministic encoding such as `base64url` or `percent-encode` with a reserved separator, and store the raw resource ID inside `lock.json` for human readability.
