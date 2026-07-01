---
name: codebase-onboarding
description: "Catalogue unfamiliar codebases into an onboarding guide — architecture, entry points, conventions. Use when joining or taking over a project. Don't use for single-file lookups."
metadata:
  origin: ECC
---

# Codebase Onboarding

Systematically analyze an unfamiliar codebase and produce a structured onboarding guide. Designed for developers joining a new project or setting up Claude Code in an existing repo for the first time.

## When to Use

- First time opening a project with Claude Code
- Joining a new team or repository
- User asks "help me understand this codebase"
- User asks to generate a CLAUDE.md for a project
- User says "onboard me" or "walk me through this repo"

## How It Works

### Phase 1: Reconnaissance

Gather raw signals about the project without reading every file. Run these checks in parallel:

```
1. Package manifest detection
   → package.json, go.mod, Cargo.toml, pyproject.toml, pom.xml, build.gradle,
     Gemfile, composer.json, mix.exs, pubspec.yaml

2. Framework fingerprinting
   → next.config.*, nuxt.config.*, angular.json, vite.config.*,
     django settings, flask app factory, fastapi main, rails config

3. Entry point identification
   → main.*, index.*, app.*, server.*, cmd/, src/main/

4. Directory structure snapshot
   → Top 2 levels of the directory tree, ignoring node_modules, vendor,
     .git, dist, build, __pycache__, .next

5. Config and tooling detection
   → .eslintrc*, .prettierrc*, tsconfig.json, Makefile, Dockerfile,
     docker-compose*, .github/workflows/, .env.example, CI configs

6. Test structure detection
   → tests/, test/, __tests__/, *_test.go, *.spec.ts, *.test.js,
     pytest.ini, jest.config.*, vitest.config.*
```

### Phase 2: Architecture Mapping

From the reconnaissance data, identify:

**Tech Stack**
- Language(s) and version constraints
- Framework(s) and major libraries
- Database(s) and ORMs
- Build tools and bundlers
- CI/CD platform

**Architecture Pattern**
- Monolith, monorepo, microservices, or serverless
- Frontend/backend split or full-stack
- API style: REST, GraphQL, gRPC, tRPC

**Key Directories**
Map the top-level directories to their purpose, using what reconnaissance actually detected — not a template. A directory whose purpose isn't confidently inferable from its contents gets flagged, not guessed.

**Data Flow**
Trace one request from entry to response:
- Where does a request enter? (router, handler, controller)
- How is it validated? (middleware, schemas, guards)
- Where is business logic? (services, models, use cases)
- How does it reach the database? (ORM, raw queries, repositories)

### Phase 3: Convention Detection

Identify patterns the codebase already follows:

**Naming Conventions**
- File naming: kebab-case, camelCase, PascalCase, snake_case
- Component/class naming patterns
- Test file naming: `*.test.ts`, `*.spec.ts`, `*_test.go`

**Code Patterns**
- Error handling style: try/catch, Result types, error codes
- Dependency injection or direct imports
- State management approach
- Async patterns: callbacks, promises, async/await, channels

**Git Conventions**
- Branch naming from recent branches
- Commit message style from recent commits
- PR workflow (squash, merge, rebase)
- If the repo has no commits yet or only a shallow history (e.g. `git clone --depth 1`), skip this section and note "Git history unavailable or too shallow to detect conventions"

### Phase 4: Generate Onboarding Artifacts

Produce two outputs:

#### Output 1: Onboarding Guide

Structure (every field populated from what reconnaissance actually detected, never a fabricated example):

```markdown
# Onboarding Guide: [Project Name]

## Overview
[2-3 sentences: what this project does and who it serves]

## Tech Stack
[Detected language, framework, database, ORM, test runner — with versions]

## Architecture
[Diagram or description of how components connect]

## Key Entry Points
[Detected route handlers, pages, data-model source of truth, build config]

## Directory Map
[Top-level directory → purpose mapping]

## Request Lifecycle
[Trace one API request from entry to response]

## Conventions
- [File naming pattern]
- [Error handling approach]
- [Testing patterns]
- [Git workflow]

## Common Tasks
[Detected dev/test/lint/migrate/build commands]

## Where to Look
[I-want-to → file-path table, populated from Key Entry Points + Directory Map]
```

#### Output 2: Starter CLAUDE.md

Generate or update a project-specific CLAUDE.md based on detected conventions. If `CLAUDE.md` already exists, read it first and enhance it — preserve existing project-specific instructions and clearly call out what was added or changed.

```markdown
# Project Instructions

## Tech Stack
[Detected stack summary]

## Code Style
- [Detected naming conventions]
- [Detected patterns to follow]

## Testing
- Run tests: `[detected test command]`
- Test pattern: [detected test file convention]
- Coverage: [if configured, the coverage command]

## Build & Run
- Dev: `[detected dev command]`
- Build: `[detected build command]`
- Lint: `[detected lint command]`

## Project Structure
[Key directory → purpose map]

## Conventions
- [Commit style if detectable]
- [PR workflow if detectable]
- [Error handling patterns]
```

## Best Practices

1. **Don't read everything** — reconnaissance should use Glob and Grep, not Read on every file. Read selectively only for ambiguous signals.
2. **Verify, don't guess** — if a framework is detected from config but the actual code uses something different, trust the code.
3. **Respect existing CLAUDE.md** — if one already exists, enhance it rather than replacing it. Call out what's new vs existing.
4. **Stay concise** — the onboarding guide should be scannable in 2 minutes. Details belong in the code, not the guide.
5. **Flag unknowns** — if a convention can't be confidently detected, say so rather than guessing. "Could not determine test runner" is better than a wrong answer.

## Anti-Patterns to Avoid

- Generating a CLAUDE.md that's longer than 100 lines — keep it focused
- Listing every dependency — highlight only the ones that shape how you write code
- Describing obvious directory names — `src/` doesn't need an explanation
- Copying the README — the onboarding guide adds structural insight the README lacks

## Examples

### Example 1: First time in a new repo
**User**: "Onboard me to this codebase"
**Action**: Run full 4-phase workflow → produce Onboarding Guide + Starter CLAUDE.md
**Output**: Onboarding Guide printed directly to the conversation, plus a `CLAUDE.md` written to the project root

### Example 2: Generate CLAUDE.md for existing project
**User**: "Generate a CLAUDE.md for this project"
**Action**: Run Phases 1-3, skip Onboarding Guide, produce only CLAUDE.md
**Output**: Project-specific `CLAUDE.md` with detected conventions

### Example 3: Enhance existing CLAUDE.md
**User**: "Update the CLAUDE.md with current project conventions"
**Action**: Read existing CLAUDE.md, run Phases 1-3, merge new findings
**Output**: Updated `CLAUDE.md` with additions clearly marked

1. verify the onboarding guide against the live code — confirm every entry point + convention named actually exists in the repo.
   If a claim drifts from what the code does (detected vs actual differ), trust the code — never ship a guide that guesses when it could verify.
