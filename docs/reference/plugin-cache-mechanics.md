# Plugin cache mechanics: dev-machine directory registration vs. a GitHub fetch

On a dev machine the marketplace is usually registered as a local directory, not the
`wasikarn/matt-harness` GitHub repo. Check `~/.claude/plugins/known_marketplaces.json`: a
`"source": "directory"` entry pointing at the clone means `claude plugin update` copies the
**working tree**, not a git checkout, so gitignored files travel into the cache along with the
shipped surfaces. Two consequences worth knowing before reading a cache directory as if it were
the repo:

- `installed_plugins.json` still records a `gitCommitSha`, which makes the cache look
  git-derived when it is not. Untracked and gitignored content sits there anyway.
- Eval fixture workspaces (`*-workspace/`, gitignored) get copied on every version bump. One
  `node_modules` tree under `deep-audit-workspace/` put 116 MB into each cached version before
  anyone noticed, because nothing reports cache size. Prune `node_modules` out of fixture
  workspaces rather than deleting the workspaces themselves; the eval artifacts are small and
  worth keeping, the deps regenerate from their own `package.json`.
- **This is a different mechanism from `marketplace.json`'s own per-plugin `source` field**
  (confirmed against `code.claude.com/docs/en/plugin-marketplaces.md`, 2026-08-29, and
  re-verified empirically against this machine's live cache the same day — `*-workspace/`,
  `.DS_Store`, `__pycache__/` are all present in
  `~/.claude/plugins/cache/wasikarn/mh/<version>/` right now). That doc states a plugin entry's
  own `"source": "./relative/path"` (or `github`/`git`/`npm`/`archive`) *does* filter gitignored
  content when a marketplace is fetched normally — this repo's own
  `.claude-plugin/marketplace.json` uses exactly that field type (`"source": "."`) and would
  behave that way if fetched over git or npm. The gitignored-content leak described above is
  specific to `known_marketplaces.json`'s *marketplace-level* `"source": "directory"`
  registration (how the whole marketplace repo itself got onto this machine, via
  `claude plugin marketplace add <local-path>`) — a separate, undocumented-by-that-page code
  path with no such filtering, because it's a plain local mirror, not a fetch.

None of this reaches anyone installing from GitHub. Their copy is the git tree, where those paths
do not exist.
