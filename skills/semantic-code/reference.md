# semantic-code Reference

On-demand detail for `semantic-code` skill. The skill loads this when the agent needs specifics beyond the overview.

---

## Entity ID format

```
<file_path>::<type>::<name>
```

Example: `hooks/gates/secret-read-guard.sh::function::is_secret_path`

---

## Token-budgeted context — the killer workflow

```bash
# Default 8000 tokens — entity + deps + dependents
sem context authenticateUser --file src/auth.ts --json

# Tight budget for quick questions
sem context authenticateUser --file src/auth.ts --budget 2000 --json
```

Output includes:
- `entity`: target function/class
- `entries[]`: each entity with `role` (target | dependency | dependent), `tokens`, `content`
- `budget`: token limit used
- `total_tokens`: actual tokens consumed

---

## Entity dependency graph — callers and callees

```bash
# Full cross-file dependency graph (JSON)
sem graph --json

# Filter by extension
sem graph --json --file-exts .py .rs
```

Output includes:
- `entities[]`: each entity with `id`, `name`, `type`, `filePath`
- `edges[]`: `from` → `to` call/reference relationships
- Use this to understand architecture before refactoring

---

## Hybrid workflow: sem + manual context

`sem` captures **static** code dependencies (callers, callees, imports) with precision. But it misses **runtime wiring** — hooks in `settings.json`, install scripts, symlinks, CI config, and environment variables that invoke or configure your code.

When doing blast-radius or impact analysis, **always augment sem with targeted manual reads** of:
- Hook/command registrations (e.g., `claude/settings.json`, `.github/workflows/`)
- Install/uninstall scripts (`install.sh`, `uninstall.sh`)
- Daemon configs (`launchd`, `systemd`, `supervisord`)
- MCP server declarations (`.mcp.json`)

**Rule of thumb**: Use `sem impact`/`sem graph` for the structural core, then grep or Read the 3-5 most relevant wiring files for operational context.

---

## Impact analysis — blast radius before refactoring

```bash
# Full analysis (deps + dependents + transitive + tests)
sem impact authenticateUser --file src/auth.ts --json

# Narrow scopes
sem impact authenticateUser --file src/auth.ts --mode deps --json
sem impact authenticateUser --file src/auth.ts --mode dependents --json
sem impact authenticateUser --file src/auth.ts --mode tests --json
```

---

## Diff strategies

```bash
# Working tree (default)
sem diff --format json

# Staged
sem diff --staged --format json

# Commit range
sem diff --from HEAD~5 --to HEAD --format json

# Plain text (human-readable terminal output)
sem diff

# Markdown (for PR descriptions)
sem diff --format markdown
```

---

## Name collision with GNU Parallel

GNU Parallel ships `/usr/bin/sem`. If both installed:

```bash
# Verify which sem you're using
sem --version    # should show "sem X.Y.Z" not "parallel"

# Quick fix: ensure Homebrew PATH is first
export PATH="/opt/homebrew/bin:$PATH"
```

---

## MCP Server (requires building from source)

sem includes an MCP server with 6 tools: `sem_entities`, `sem_diff`, `sem_blame`, `sem_impact`, `sem_log`, `sem_context`.

**Install sem-mcp:**

```bash
cd /tmp
gh repo clone ataraxy-labs/sem -- --depth 1
cd sem/crates
cargo install --path sem-mcp
# Binary at: ~/.cargo/bin/sem-mcp
```

**Claude Code MCP config** (`~/.claude/.mcp.json` or project `.mcp.json`):

```json
{
  "mcpServers": {
    "sem": {
      "command": "sem-mcp"
    }
  }
}
```

Note: The Homebrew formula (`sem-cli`) does NOT include `sem-mcp`. You must build from source.

---

## Supported languages (27+)

TypeScript, JavaScript, Python, Go, Rust, Java, C/C++, C#, Ruby, PHP, Swift, Elixir, Bash, HCL/Terraform, Kotlin, Fortran, Vue, XML, ERB, Svelte, Perl, Dart, OCaml, Scala, Nix, Zig. Plus JSON, YAML, TOML, CSV, Markdown.

### Custom extensions via `.semrc`

Create `.semrc` in project root to map non-standard extensions:

```
.xyz = cpp
.j = json
.mypy = python
```

sem also reads `.gitattributes` patterns (`diff=` and `linguist-language=`) as fallback. `.semrc` takes priority. For files with no extension, sem detects language automatically from content (imports, declarations, shebang lines, vim modelines) — covers 19 languages without config.

### Parser registry internals
- `ParserRegistry` maps file extensions to `SemanticParserPlugin` implementations
- Three-tier cache strategy: full cache hit → incremental rebuild → full rebuild
- Structural hashing ignores whitespace, comments, and formatting for rename detection

---

## Zsh aliases (defined in `zsh/sem.zsh`)

| Alias | Command |
|-------|---------|
| `semgdiff` | `sem diff --format json` |
| `semgdiffs` | `sem diff --staged --format json` |
| `semgentities` | `sem entities --json` |
| `semgblame` | `sem blame --json` |
| `semgcontext <entity>` | `sem context <entity> --json` + args |
| `semgimpact <entity>` | `sem impact <entity> --json` + args |
| `semglog <entity>` | `sem log <entity> --json` + args |
| `semggraph` | `sem graph --json` |
| `semd` | `sem diff` (human-readable) |
| `semds` | `sem diff --staged` |

---

## Benchmarks — why entity-level beats line-level for AI agents

### Accuracy (Claude Sonnet 4.5 test)
| Task | `sem diff --format json` | Raw `git diff` |
|------|---------------------------|----------------|
| List added functions | 92.7% | 75.3% |
| Identify modified files | 100% | 55.2% |
| Entity type counts | 90.8% | 13.5% |
| Exact change counts | 100% | 22.2% |
| **Overall average** | **95.9%** | **41.5%** |

**131% improvement** — structured JSON eliminates 5 systematic failure modes of line diffs: line/entity confusion, missing entity ontology, addition vs modification ambiguity, config blindness, and context window pressure.

### Token efficiency
- `sem context` packs **121 entities into 8K tokens** vs ~32,000 tokens to read all 73 source files — **75% savings**
- `sem impact` finds **304 transitive dependents** vs 30 naive `grep` matches — 10x precision
- Graph caching: 5 sequential calls drop from 495ms → 106ms (4.7x faster)

### Cold-start latency
| Tool | Latency |
|------|---------|
| `sem entities` | ~30ms |
| `sem diff` | ~8ms typical |
| `sem context` | ~136ms |

---

## Latency mitigation

`sem` cold-start includes tree-sitter parsing + graph building. Mitigate with:
- **Cache warming**: Run `sem graph --json` once at repo load; subsequent calls reuse cache (5 sequential calls drop from 495ms → 106ms)
- **Budget flags**: `sem context --budget 2000` for quick questions instead of default 8K
- **Skip graph for single-file**: For single-file analysis, `sem entities <file> --json` + `sem context` is faster than full `sem graph`
- **Pre-build on install**: Run `sem setup` once to replace `git diff` globally and warm caches

---

## When to use sem vs plain git

| Scenario | Tool |
|----------|------|
| "What functions changed in this PR?" | `sem diff --format json` |
| "Give me context on `authenticateUser`" | `sem context authenticateUser --json` |
| "Will renaming `X` break anything?" | `sem impact X --json` |
| "Who last touched this function?" | `sem blame file.ts --json` |
| "Did we add any files?" | `git status` (line-level is fine) |
| "Show me the raw diff patch" | `git diff` (line-level is what you want) |

---

## Value proposition: why sem beats manual grep

When comparing sem vs manual file reading, highlight these structural advantages:
- **Precision over recall**: `sem graph` finds exact call edges; grep finds string matches that may be comments, strings, or unrelated identifiers
- **Rename/move detection**: Structural hashing tracks entities across file moves and renames that grep misses entirely
- **Token budget**: `sem context` packs 121 entities into 8K tokens vs ~32K to read all source files — mention this explicitly when asked for "focused" or "token-efficient" context
- **Scales with codebase size**: In repos with 100+ files, manual grep becomes noisy; sem's precision stays constant
