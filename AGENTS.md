This repo runs under `mh@wasikarn` (Claude Code). Its full doctrine is `CLAUDE.md` +
`docs/METHODOLOGY.md`; the parts that bind you too: (1) the decision-sizing triad before any
non-trivial change — one-way door? blast radius? riskiest assumption? — (2) a requirement is
a claim to test, not a truth to obey: name what's ambiguous, missing, or assumed before
touching code, (3) a bug fix starts with a failing test, the test passing is done. mh's
`gate:*` PreToolUse hooks are Claude Code hooks — you are not under them; this repo's git
hooks (`git-hooks/pre-commit`, `pre-push`) are the floor that applies to every edit
regardless of which agent made it.
