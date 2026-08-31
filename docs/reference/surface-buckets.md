# Surface bucket naming: skills vs. agents

Skills and agents bucket differently — don't apply one rule to both.

A new **skill** buckets by folder placement (`skills/<bucket>/<name>/SKILL.md`), not
frontmatter — the old `bucket:` frontmatter check on skills was retired in the 2026-08-25 folder
migration; harness-audit check 05 now derives the bucket from the path itself, CRITs on an
unrecognized bucket dir name, and WARNs (degraded `BOUNDARY.md` grouping only, still loads) on a
flat `skills/<name>/SKILL.md` with no bucket dir at all. Skill buckets: `meta`/`review`/
`patterns`/`agent-support`/`design`/`workflow`.

A new **agent** still needs `bucket:` frontmatter (top-level key, right after `description:`) —
`agents/*.md` stays flat, not folder-bucketed, and check 04 WARNs if it's missing. Agent buckets:
`design`/`review`/`build`/`analysis`/`utility`.

Both group the `BOUNDARY.md` tables.

**A brand-new top-level `skills/` bucket** (a 7th folder alongside the 6 above) additionally
needs its path added to `.claude-plugin/plugin.json`'s own `skills` array — that array, once
declared, *replaces* the default `skills/` directory scan rather than adding to it (an
official-docs-confirmed marketplace-root exception, 2026-08-29), so an undeclared bucket is
silently invisible to skill discovery even though the files exist on disk.
