:warning: **Reference-only.** This was formerly the `semantic-code` skill; it is no longer a loadable `kbg:` surface. Use the `sem` CLI directly when you need entity-level diff or context.

# semantic-code — Semantic Version Control

Repo: https://github.com/ataraxy-labs/sem  
Install: `brew install sem-cli` (already present at `/opt/homebrew/bin/sem`)

## Philosophy

`sem` parses code with tree-sitter and diffs at the **entity level** (function, class, method, struct, trait) instead of line level. This means:

- "function `authenticateUser` was modified" — not "lines 42-87 changed"
- Rename/move detection via structural hashing
- Token-budgeted context (`sem context`) — the killer feature for LLMs

## CLI Commands (JSON output for agents)

| Command | Purpose | AI Agent Use |
|---------|---------|--------------|
| `sem diff --format json` | Entity-level diff of working changes | Replace `git diff` when you need semantic understanding |
| `sem diff --staged --format json` | Staged changes only | Pre-commit review |
| `sem diff --commit abc123 --format json` | Specific commit | PR review |
| `sem entities [path] --json` | List functions/classes/methods | Map codebase structure |
| `sem blame <file> --json` | Entity-level authorship | Find who owns a function |
| `sem impact <entity> --file <file> --json` | Cross-file dependency blast radius | Assess refactor risk |
| `sem log <entity> --json` | Entity history through git | Trace evolution |
| `sem context <entity> --file <file> --json` | Token-budgeted context (default 8K tokens) | **Primary tool** — feed to LLM |
| `sem graph --json` | Cross-file entity dependency graph | Map callers/callees |
| `sem setup` / `sem unsetup` | Replace `git diff` globally | One-time config |

## Entity ID format

```
<file_path>::<type>::<name>
```

Example: `hooks/gates/secret-read-guard.sh::function::is_secret_path`

## Token-budgeted context

```bash
sem context authenticateUser --file src/auth.ts --json        # 8K tokens default
sem context authenticateUser --file src/auth.ts --budget 2000 # tight budget
```

Output includes:
- `entity`: target function/class
- `entries[]`: each entity with `role` (target | dependency | dependent), `tokens`, `content`
- `budget`: token limit used
- `total_tokens`: actual tokens consumed

## Entity dependency graph

```bash
sem graph --json
sem graph --json --file-exts .py .rs
```

Output includes `entities[]` and `edges[]` (caller/callee relationships).

## Impact analysis — blast radius before refactoring

```bash
sem impact authenticateUser --file src/auth.ts --json
sem impact authenticateUser --file src/auth.ts --mode deps --json
sem impact authenticateUser --file src/auth.ts --mode dependents --json
sem impact authenticateUser --file src/auth.ts --mode tests --json
```

## Diff strategies

```bash
sem diff --format json
sem diff --staged --format json
sem diff --from HEAD~5 --to HEAD --format json
sem diff --format markdown
```

## Hybrid workflow: sem + manual context

`sem` captures **static** code dependencies with precision, but misses **runtime wiring** — hooks in `settings.json`, install scripts, symlinks, CI config, and environment variables. When doing blast-radius analysis, augment `sem` with targeted manual reads of the 3-5 most relevant wiring files.

## Name collision with GNU Parallel

GNU Parallel ships `/usr/bin/sem`. Verify with `sem --version` (should show "sem X.Y.Z", not "parallel"). If wrong, ensure Homebrew PATH is first: `export PATH="/opt/homebrew/bin:$PATH"`.

## MCP Server

sem includes an MCP server with 6 tools (`sem_entities`, `sem_diff`, `sem_blame`, `sem_impact`, `sem_log`, `sem_context`). The Homebrew formula does NOT include `sem-mcp`; build from source if needed. See the upstream repo for instructions.

## Supported languages

27+ languages including TypeScript, JavaScript, Python, Go, Rust, Java, C/C++, C#, Ruby, PHP, Swift, Elixir, Bash, HCL/Terraform, Kotlin, Fortran, Vue, XML, ERB, Svelte, Perl, Dart, OCaml, Scala, Nix, Zig, plus JSON, YAML, TOML, CSV, Markdown.

### Custom extensions via `.semrc`

```
.xyz = cpp
.j = json
.mypy = python
```

`.semrc` takes priority; `.gitattributes` (`diff=` / `linguist-language=`) is fallback. Files without extension are detected from content.

## When to use sem vs plain git

| Scenario | Tool |
|----------|------|
| "What functions changed in this PR?" | `sem diff --format json` |
| "Give me context on `authenticateUser`" | `sem context authenticateUser --json` |
| "Will renaming `X` break anything?" | `sem impact X --json` |
| "Who last touched this function?" | `sem blame file.ts --json` |
| "Did we add any files?" | `git status` |
| "Show me the raw diff patch" | `git diff` |

## Value proposition

- **Precision over recall**: exact call edges vs noisy grep
- **Rename/move detection**: structural hashing tracks entities across file moves
- **Token efficiency**: `sem context` packs 121 entities into 8K tokens vs ~32K to read all source files
- **Scales with codebase size**: precision stays constant as the repo grows
