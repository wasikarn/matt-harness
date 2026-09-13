#!/usr/bin/env bash
mkdir -p agents skills/meta/demo/scripts hooks/gates
cat > agents/checker.md <<'FIXTURE_EOF'
---
name: checker
description: "Reviews a diff for swallowed errors. Use when a PR touches try/catch or fallbacks."
bucket: utility
tools: Read, Grep
model: sonnet
effort: low
---

Read-only reviewer; returns findings, never edits.
FIXTURE_EOF
cat > skills/meta/demo/SKILL.md <<'FIXTURE_EOF'
---
name: demo
description: "Prints the fleet's version. Use when asked which demo version is installed."
model: inherit
effort: low
---

# demo

Run `bash "${CLAUDE_SKILL_DIR}/scripts/version.sh"`.
FIXTURE_EOF
printf '#!/usr/bin/env bash\necho 1.0.0\n' > skills/meta/demo/scripts/version.sh
printf '#!/usr/bin/env bash\necho "${CLAUDE_PLUGIN_ROOT:-}"\n' > hooks/gates/noop.sh
cat > hooks/hooks.json <<'FIXTURE_EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/gates/noop.sh\"","timeout":8}]}]}}
FIXTURE_EOF
sed -i.bak 's/^name: demo$/name: demo-skill/' skills/meta/demo/SKILL.md && rm skills/meta/demo/SKILL.md.bak
sed -i.bak '/^tools: /d' agents/checker.md && rm agents/checker.md.bak
