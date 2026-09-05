# Composer-not-creator doctrine

Before writing a new skill or agent from scratch, check sources in this order:

1. **`mattpocock/skills` first.** What is installed under the `mattpocock-skills@mattpocock`
   plugin (`claude plugin list`, namespaced `mattpocock-skills:<name>`), plus the local clone
   at `~/Codes/Personals/mattpocock-skills` if this machine has it, for what is upstream but not
   yet installed. This is a Matt-Pocock-first harness; checking ECC or superpowers before
   matt's own repo gets the priority backwards. If the clone exists, `git fetch` it before
   trusting it: the installed plugin can be newer than the clone (it silently lagged
   `origin/main` by a full minor release once).
2. If present: `~/Codes/Personals/ECC` and `~/Codes/Personals/superpowers`.
3. If present: sibling harnesses under `~/Codes/Personals/` for structural patterns.

Cherry-pick and adapt from whichever fits; create a native surface only when none do. Skipping
(1) has collided with matt's own work before (2026-07-17: a `code-implementer` agent built
against (2) and (3) duplicated `/mattpocock-skills:implement`; the user caught it, not the
checklist). None of these clones ship with the plugin; on a machine without them, the installed
plugin is the only source.

A clone reached via `claude --add-dir` loads none of its own CLAUDE.md by default; set
`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` if you need its instructions, not just its files.

## Vetting a third-party plugin or skill

A skill gives Claude new capabilities through instructions and code, so treat installing one
like installing software. Before relying on a new plugin, MCP server, or skill: read its
SKILL.md and scripts once for the network calls, file writes, and Bash commands it can trigger,
and confirm they match its stated purpose.
