# Adding or removing a surface

Moved out of the root `CLAUDE.md` 2026-09-03 (lookup material, loaded on demand; the pointer
there is the ambient part).

Auto-discovered directories this plugin currently uses: `agents/`, `skills/`, `hooks/`,
`output-styles/`, `themes/` (`commands/` retired as a surface type 2026-08-25, #112) — this is
"the 5 this plugin ships," not an exhaustive list of what Claude Code plugins support more
broadly (`workflows/`, `.mcp.json`, `.lsp.json`, `monitors/monitors.json`, `bin/`, and a
plugin-root `settings.json` are also real, just unused here — confirmed against
`code.claude.com/docs/en/plugins-reference.md`, 2026-08-29). Drafting a brand-new skill's
content from scratch (the interview → draft SKILL.md → eval → iterate loop) is what the
installed `skill-creator:skill-creator` skill is for — run that first, then continue with
step 1 below for the file's placement and step 3 onward for shipping it; skill-creator has
no awareness of this repo's own manifest/version-bump/BOUNDARY.md ritual. The step-by-step
(inlined from the removed `add-surface` skill, 2026-08-24 #80):

1. Create/remove the file(s), following the pattern of an existing component in the same
   directory. **Skills and agents bucket differently — don't apply one rule to both.** A
   **skill** buckets by folder placement (`skills/<bucket>/<name>/SKILL.md`); an **agent** needs
   `bucket:` frontmatter instead (`agents/*.md` stays flat). Full bucket lists, the harness-audit
   checks that enforce each (check 05 for skills, check 04 for agents), and the brand-new-
   top-level-bucket `plugin.json` gotcha: `docs/reference/surface-buckets.md`.
2. Hooks: register/deregister in `hooks/hooks.json`; add tests for any gate. After removing
   a hook's test section, grep the ENTIRE test file (not just the deleted section) for every
   shared helper function's name and remove any with zero remaining callers.
3. Bump both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions.
   Same-version edits to a cached plugin are silent no-ops.
4. Run `bash skills/inventory/scripts/sync-fleet-counts.sh` to patch the "N skills · M
   agents" pair into `plugin.json`/`marketplace.json`/`README.md`. A new **agent** also
   needs two hand edits the script can't reach: `skills/workflow/orchestrate/routing.md`'s
   named routing table + "N-agent survivor set" count, and the count mention in
   `docs/agent-voice-extension.md`.
5. Run `claude plugin validate . --strict`, then `bash
   skills/meta/harness-audit/scripts/audit.sh` and fix any WARN. A CRIT F1 ("not loadable")
   for a brand-new component is expected here; it clears at step 6.
6. `claude plugin update mh@wasikarn` **before** committing. The pre-commit hook's
   harness-audit F1 check only sees the latest *cached* plugin version, so a brand-new file
   blocks as CRIT F1 until this refreshes the cache.
7. Regenerate `BOUNDARY.md` (see the regen gotcha in `docs/reference/repo-gotchas.md`),
   commit, push, restart Claude Code.

## Finding a surface

Read `BOUNDARY.md` first: the generated, always-current index of every agent, skill,
command, and hook, grouped by `bucket:` (skills and agents) since schema v5. Then the
specific `SKILL.md`/agent file for detail. Routing questions go to
`/mattpocock-skills:ask-matt`. The former kbg router layers (`/kbg-help`, `/kbg:ask-kbg`)
were removed 2026-08-24 (#80).
