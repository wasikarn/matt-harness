# Vetting a new third-party plugin/skill before relying on it

Distinct concern from CLAUDE.md's composer-not-creator sourcing-priority list (that's about
where to *look* when *authoring*; this is about *trusting* something already installed).
Anthropic's own Agent Skills security guidance says treat installing a skill like installing
software — a skill gives Claude new capabilities through instructions and code, so a malicious
or careless one can direct tool/Bash use that doesn't match its stated purpose (confirmed against
`platform.claude.com/.../agent-skills/overview.md`, 2026-08-29). Before relying on a **new**
third-party plugin, MCP server, or skill for real work: read its SKILL.md/scripts once for what
network calls, file writes, or Bash commands it can actually trigger, especially anything with
credential or payment-data access; skills that fetch external URLs carry particular risk, since
fetched content can itself carry instructions. This is a forward practice, applied at the point
of adding something new — not a standing retroactive-audit schedule.

A one-time retroactive pass over every plugin installed at the time (`diagram-design`, `eli5`,
`mattpocock-skills`, `plannotator-effective-html`, `ponytail`, `qmd`, `superset` — Anthropic's own
first-party bundle excluded as lower-risk) ran 2026-08-29: all 7 came back clean (no unexpected
network calls, exec, or credential handling beyond stated purpose), with two named limits (qmd's
compiled binary and the standalone `superset` app itself couldn't be inspected, only their
skill-layer wrappers). Full method and per-plugin findings: the
`third-party-plugin-vetting-pass-2026-08-29` memory. Applies to any plugin added **after** that
date going forward.
