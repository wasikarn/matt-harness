#!/usr/bin/env bash
mkdir -p memory
cat > memory/MEMORY.md <<'FIXTURE_EOF'
# Memory index

Index only: one line per memory. Detail lives in the linked file.

## Sub-indexes
- [Ops gotchas](index-ops.md) — shell/tooling gotchas, indexed separately.
FIXTURE_EOF
cat > memory/index-ops.md <<'FIXTURE_EOF'
---
name: index-ops
description: "Sub-index: shell/tooling gotchas"
metadata:
  type: reference
---

- [Trash with empty arg deletes cwd](trash-empty-guard.md) — validate non-empty before `trash`.
FIXTURE_EOF
cat > memory/trash-empty-guard.md <<'FIXTURE_EOF'
---
name: trash-empty-guard
description: trash with an empty argument removes the current directory
metadata:
  type: feedback
---

Validate the argument is non-empty before calling `trash`.

**Why:** an empty variable expanded to nothing and the cwd was trashed.
**How to apply:** guard every `trash "$x"` with a non-empty test.
FIXTURE_EOF
cat > transcript.jsonl <<'FIXTURE_EOF'
{"type":"user","message":{"role":"user","content":"hey remember this -- if a bash variable is empty and you call trash on it, it wipes the current directory, always check the variable isn't empty first"}}
{"type":"assistant","message":{"role":"assistant","content":"Understood, I'll always guard trash calls against an empty argument."}}
{"type":"user","message":{"role":"user","content":"also, always run the linter before every commit in this repo -- we shipped a broken lint state twice by skipping it"}}
{"type":"assistant","message":{"role":"assistant","content":"Got it, I'll always run the linter before committing here."}}
FIXTURE_EOF
