#!/usr/bin/env bash
mkdir -p memory
cat > memory/MEMORY.md <<'FIXTURE_EOF'
# Memory index

- [Gate hooks break machine-wide](gate-hooks-break-machine-wide.md) — on a lockout, check every session.
- [Push needs a remote check](push-needs-remote-check.md) — ls-remote before saying it landed.
- [Trash with empty arg deletes cwd](trash-empty-arg-deletes-cwd.md) — validate non-empty first.
FIXTURE_EOF
cat > memory/gate-hooks-break-machine-wide.md <<'FIXTURE_EOF'
---
name: gate-hooks-break-machine-wide
description: A broken PreToolUse gate locks out every session on the machine, not just the tree-sharing ones
metadata:
  type: project
---

A gate hook that exits non-zero on every call blocks Bash in every live session, because the plugin cache is machine-wide.

**Why:** the hook runs from one cache path for all sessions.
**How to apply:** on a lockout, check every session, not only the ones sharing this tree. Related: [[push-needs-remote-check]].
FIXTURE_EOF
cat > memory/push-needs-remote-check.md <<'FIXTURE_EOF'
---
name: push-needs-remote-check
description: A push reported as successful must be confirmed with an independent remote check
metadata:
  type: feedback
---

Run `git ls-remote` after a push before reporting it landed.

**Why:** a hook rejected a push once while the terminal showed success.
**How to apply:** compare the remote SHA with HEAD. See also [[trash-empty-arg-deletes-cwd]].
FIXTURE_EOF
cat > memory/trash-empty-arg-deletes-cwd.md <<'FIXTURE_EOF'
---
name: trash-empty-arg-deletes-cwd
description: trash with an empty argument removes the current directory
metadata:
  type: feedback
---

Validate the argument is non-empty before calling `trash`.

**Why:** an empty variable expanded to nothing and the cwd was trashed.
**How to apply:** guard every `trash "$x"` with a non-empty test. Related: [[gate-hooks-break-machine-wide]].
FIXTURE_EOF
sed -i.bak 's/\[\[push-needs-remote-check\]\]/[[push-needs-remote-chekc]]/' memory/gate-hooks-break-machine-wide.md && rm memory/gate-hooks-break-machine-wide.md.bak
printf -- '- [Old orchestrate cost](orchestrate-cost-round2.md) — superseded by the rebuild.\n' >> memory/MEMORY.md
cat > memory/rm-f-silently-noops.md <<'FIXTURE_EOF'
---
name: rm-f-silently-noops
description: rm -f is a silent no-op in this environment; use trash or Python unlink in scripts
metadata:
  type: project
---

`rm -f` returns 0 and removes nothing here.

**Why:** the irrecoverable gate rewrites it.
**How to apply:** scripts delete with Python's unlink or `trash`. Related: [[trash-empty-arg-deletes-cwd]].
FIXTURE_EOF
