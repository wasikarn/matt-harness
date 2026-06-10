---
name: semantic-code
description: "Use this skill when the user asks about functions, classes, or methods — not just lines of code. Use for: what functions or classes changed in commits or PRs, history of a specific function or class, cross-file dependency graphs showing callers and callees, whether refactoring or renaming will break things, and token-budgeted context on a specific entity. Do NOT use for: plain git operations like raw diffs, file listings, or simple blame."
---

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

## Quick workflows

**Entity ID format:** `<file_path>::<type>::<name>`  
Example: `claude/hooks/secret-read-guard.sh::function::is_secret_path`

**Token-budgeted context** (killer feature for LLMs):
```bash
sem context authenticateUser --file src/auth.ts --json        # 8K tokens default
sem context authenticateUser --file src/auth.ts --budget 2000 # tight budget
```

**Impact / blast radius**:
```bash
sem impact authenticateUser --file src/auth.ts --json
```

**Dependency graph**:
```bash
sem graph --json
```

## When to use sem vs plain git

| Scenario | Tool |
|----------|------|
| "What functions changed in this PR?" | `sem diff --format json` |
| "Give me context on `authenticateUser`" | `sem context authenticateUser --json` |
| "Will renaming `X` break anything?" | `sem impact X --json` |
| "Who last touched this function?" | `sem blame file.ts --json` |
| "Did we add any files?" | `git status` (line-level is fine) |
| "Show me the raw diff patch" | `git diff` (line-level is what you want) |

See [reference.md](reference.md) for: full command options, diff strategies, MCP server setup, benchmarks, latency mitigation, zsh aliases, supported languages, and the hybrid `sem + manual context` workflow.
