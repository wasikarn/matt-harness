# Post-Mortem: Check 62's Allowlist Parse Fails Silent Instead of Loud (`check62-allowlist-crash-2026-08-21`)

## 1. Summary

harness-audit check 62 (cross-file content-drift detection, shipped in `834204fe` as part of GH #72) read its allowlist file (`skills/harness-audit/accepted-duplication.tsv`) with no exception handling and no encoding-error tolerance. A malformed or unreadable allowlist file crashed the embedded `python3` process uncaught, and because the check invokes that process through bash's `<(...)` process substitution, `set -euo pipefail` never saw the failure — the check silently reported 0 WARN / 0 CRIT instead of surfacing that it had broken. Found by a fresh-context adversarial audit (`/kbg:deep-audit`) the same day the check shipped, before any real allowlist corruption occurred. Fixed in `252b2e6a`.

## 2. Symptom

Running `bash skills/harness-audit/scripts/audit.sh --only 62` (or the full audit) against a corrupted or unreadable `accepted-duplication.tsv` produced `Critical: 0 / Warnings: 0 / Info: 0` — a clean report — with no indication anything had gone wrong. No error, no traceback, no nonzero exit code from `audit.sh` itself.

## 3. Root Cause (Mechanism)

`skills/harness-audit/scripts/checks/62-cross-file-content-drift.sh` invoked an embedded Python script via:

```bash
while IFS=$'\t' read -r _fa _fb _jsim _snip; do ...
done < <(python3 - "$CLAUDE_DIR" <<'PY' ... PY)
```

Inside that script, the allowlist read had no safety net:

```python
with open(allow_path, encoding="utf-8") as fh:
    for line in fh:
        ...
```

Every other file read in the same script (`blocks_of()`) wraps its `open()` in `try/except Exception` and passes `errors="replace"`. This one read didn't. An invalid UTF-8 byte, or a permission error, raised an uncaught exception inside the Python process. Because that process runs inside a bash process-substitution (`<(...)`), its exit status is never checked by the surrounding `while read` loop — `set -euo pipefail` in the calling `audit.sh` has no visibility into a process substitution's exit code. The Python process's crash simply meant zero lines were ever written to the pipe the `while read` loop consumed.

## 4. Symptom Linkage

The allowlist read is the first thing the embedded script does after building its candidate-pair index — every `print()` statement that produces a WARN line happens *after* that read, in the same top-level script scope. An exception raised during the read terminates the whole script before any `print()` runs. Bash's `while read` loop simply sees an empty stream and exits its loop normally — it can't distinguish "the process substitution produced zero output because there was nothing to report" from "the process substitution produced zero output because it crashed." Both look identical to the calling shell: 0 WARN, 0 CRIT, exit 0.

## 5. Fix

Commit `252b2e6a` (`fix(harness-audit): silent-clean-on-crash bug in check 62's allowlist parse, v0.68.416`), on `develop`. Two changes to the allowlist read:

```python
try:
    with open(allow_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            ...
except Exception as e:
    print(f"# accepted-duplication.tsv unreadable ({e}) — allowlist not applied this run", file=sys.stderr)
```

`errors="replace"` matches `blocks_of()`'s existing convention and prevents `UnicodeDecodeError` from raising at all. The `try/except` is defense-in-depth for other IO failures (permission errors, a TOCTOU race between the `os.path.isfile()` check and the `open()` call) and prints an explicit stderr diagnostic naming the exact cause.

## 6. Discovery Method

Found by a fresh-context `general-purpose` agent dispatched via `/kbg:deep-audit`, tasked with an adversarial correctness audit of check 62 independent of the implementing session's own memory. The agent traced the allowlist-read code path for exception safety, noted it lacked the same guards as `blocks_of()`'s reads, and reproduced the failure with a synthetic `raise RuntimeError(...)` inserted mid-script inside the same process-substitution construct — confirming the outer script's `$?` stayed `0` regardless. Independently re-confirmed with a live repro against the real fixture: `chmod 000` on `accepted-duplication.tsv`, then ran `--only 62` — before the fix, this produced `0 WARN / 0 CRIT`; after the fix, the same repro produced the stderr diagnostic plus 18 WARNs (every previously-allowlisted pair correctly re-firing). The fixture was restored and diffed byte-identical to its backup afterward.

## 7. Escape Reason

Check 62 was authored, code-reviewed by a fresh-context `kbg:compliance-audit` pass, and shipped in `834204fe` the same day — but that compliance audit verified *conformance to the implementation plan* (does the code match what was specified), not *adversarial code-level correctness* (does the code handle its own failure modes). The plan never specified exception-handling behavior for the allowlist read, so there was nothing for that audit to check it against. The check's own header comment already documented a "fail loud, not silent" design principle for one failure mode (`python3` unavailable) but the allowlist-read path was added without the same discipline applied, and no code reviewer or gate independently traced every `open()` call in the file for exception safety. No test suite exists for this check's shell+embedded-Python construct, so nothing would have caught it mechanically either.

## 8. Validation Proof

Manual repro, not an automated regression test — flagged explicitly as a gap. `chmod 000 skills/harness-audit/accepted-duplication.tsv` before the fix produced `0 WARN / 0 CRIT` (the bug); the identical repro after the fix produced 18 WARNs plus the stderr diagnostic naming the permission error (the fix confirmed). CI run `32476166283` on commit `252b2e6a` completed successfully. Full gauntlet (`plugin-validate`, `shell-lint`, `json-lint`, `harness-audit`, `path-hygiene`, `hook-tests`) green on the same commit. `--only 62` against real, uncorrupted content still reports 0 WARN — no behavior change on the healthy path.

## 9. Follow-Ups

- [ ] Add an automated regression test for check 62's allowlist-read failure mode (a fixture with an invalid byte or unreadable file, asserting the check still exits with output rather than silently reporting clean) (owner: Unowned — needs assignment, done when: a test file exists under `hooks/tests/` or `skills/harness-audit/` exercising this exact scenario and is wired into the gauntlet).
- [ ] Audit every other `open()` call across the 62 harness-audit check fragments for the same unguarded-read pattern (owner: Unowned — needs assignment, done when: an audit doc lists every `open()`/file-read call per check fragment and its exception-safety verdict).
- [ ] Consider whether `audit.sh`'s process-substitution invocation pattern (used by checks #13/#28/#62, per the check's own header comment) should propagate a process's exit code explicitly, rather than relying on each embedded script never crashing (owner: Unowned — needs assignment, done when: a decision is made and, if adopted, applied consistently across all checks using this pattern).
- [ ] This is the second real defect this session found via independent fresh-context verification rather than authoring care alone (the first: check 62's own flagship justification claim was false — see the session's `verify-adversarially-before-nothing` memory entries). Consider whether a `/kbg:deep-audit`-style adversarial correctness pass should be a standing step after any new harness-audit check ships, not an ad hoc one (owner: Unowned — needs assignment, done when: a decision is documented in `docs/skill-authoring-conventions.md` or equivalent).
