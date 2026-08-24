# Phase 1 step 6 — sensitive-path check

Reference for `commands/ship-merge/COMMAND.md` Phase 1 step 6. (Filename is historical: the
scored review gate that used to live here was removed in the matt-harness migration, spec
#75 / ticket #76 — merge authorization is now Phase 2 step 5's explicit user go/no-go, and
this step's only job is the deterministic risk label that go/no-go reads. The closeout
ticket #87 owns any rename.)

**Classification.** A PR's diff is **sensitive-path** when any changed file path
(`gh pr diff <n> --name-only`) matches either leg:

- **(a) keyword regex** `auth|secret|credential|payment|billing|token`, case-insensitive —
  `commands/risk-check.md` and `hooks/gates/verifier-protect.sh` fold case for the same
  list; CHANGELOG.md documents a real bypass from skipping that fold on macOS/APFS.
- **(b) the harness's own verifier/gate paths**, classified by running each path through
  `hooks/gates/lib/_protected_paths.py`'s `is_gate_path()`:

  ```bash
  python3 -c "import sys; sys.path.insert(0,'${KBG_PLUGIN_ROOT}/hooks/gates/lib'); from _protected_paths import is_gate_path; [print(p) for p in sys.stdin.read().splitlines() if is_gate_path(p)]" <<<"$(gh pr diff <n> --name-only)"
  ```

  — the same classifier `hooks/gates/verifier-protect.sh` and `commands/risk-check.md`
  import. **Don't hardcode this path list in prose here** — it drifted silently once
  already: `hooks/advisory/**` coverage was added to the classifier 2026-08-06, and this
  guard's own hardcoded copy missed it until a doctrine-health audit (the former
  `claude-md-health` skill, removed 2026-08-24 #80) caught it 2026-08-17.

**What the result does.** Nothing computational: a **sensitive** result never STOPs Phase 1
by itself, and a **not sensitive** result never authorizes anything. Both land verbatim in
Phase 2 step 5's AskUserQuestion, so the human go/no-go — the only authorization to merge —
is made with the risk label visible, matched paths named.

**Fail closed on classification errors.** If `gh pr diff` errors, or the classifier can't
be imported, STOP and say so — never fabricate a clean label; an unclassified diff is not a
"not sensitive" diff (the same "never fabricate a clean result" rule step 7's CODEOWNERS
discovery applies to a failed fetch).
