# Composer-not-creator doctrine

Moved out of the root `CLAUDE.md` 2026-09-03; the pointer there keeps the source order, this
file keeps the reasoning and history.

Before writing a new skill, command, or agent from scratch, check sources in this order:

1. **`mattpocock/skills` first.** What's installed under the `mattpocock-skills@mattpocock`
   plugin (`claude plugin list` / the Skill tool's listing, namespaced
   `mattpocock-skills:<name>`), plus — if this machine has it — the local clone at
   `~/Codes/Personals/mattpocock-skills` for what's upstream but not yet installed. This is
   a **Matt-Pocock-first harness**; checking ECC/superpowers before matt's own repo gets the
   priority backwards. If the clone exists, `git fetch` it before trusting it: the installed
   plugin can be *newer* than the clone, inverting the "upstream but not yet installed"
   framing — confirmed the hard way once, when the clone silently lagged `origin/main` by a
   full minor release before anyone caught it. On a machine without these clones, the
   installed plugin alone is the available source — skip straight to it.
2. If present on this machine: the upstream ECC repo at `~/Codes/Personals/ECC` and the
   vendored superpowers checkout at `~/Codes/Personals/superpowers`.
3. If present: sibling harnesses under `~/Codes/Personals/` for structural patterns (e.g.
   `oh-my-claudecode`; ask if unsure which qualify).

Cherry-pick and adapt from whichever source fits; create kbg-native surfaces only when none
do. Skipping straight to (2) or (3) risks colliding with a skill matt already built — confirmed
2026-07-17, when the `code-implementer` agent and its implement slash command were built
checking only (2) and (3), skipping (1), and collided with matt's own `/mattpocock-skills:implement`
skill (caught by the user, not by this checklist). Paths are the stable anchor, not pinned
hashes — run `git rev-parse HEAD` there when
you need the current commit. None of these clones is bundled with the plugin. On a machine
without them, (1)'s installed plugin is the only available source; build kbg-native only after
checking what it already offers.

**A clone reached via `claude --add-dir` instead of `cd` loads none of its own CLAUDE.md
instructions by default** — `--add-dir` grants file access only. Set
`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` before the command if you need that clone's
own CLAUDE.md/rules read into context, not just its files.

## Vetting a new third-party plugin/skill before relying on it

Treat installing a skill like installing software — a skill gives Claude new capabilities
through instructions and code, so a malicious or careless one can direct tool/Bash use that
doesn't match its stated purpose (Anthropic's own Agent Skills security guidance). Before
relying on a **new** third-party plugin, MCP server, or skill for real work: read its
SKILL.md/scripts once for what network calls, file writes, or Bash commands it can actually
trigger. Full practice, scope, and the 2026-08-29 retroactive pass's findings:
`docs/reference/third-party-vetting.md`.
