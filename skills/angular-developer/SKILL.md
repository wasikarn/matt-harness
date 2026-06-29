---
name: angular-developer
description: "Angular code generation and architecture guidance. Covers signals, forms, DI, routing, SSR, accessibility, animations, and CLI tooling. Use when building, scaffolding, or maintaining an Angular project. Don't use for React/Vue/Svelte projects — use the framework-specific skill."
metadata:
  origin: ECC
---

# Angular Developer Guidelines

## When to Activate

- Working in any Angular project or codebase
- Creating or scaffolding a new Angular project, application, or library
- Generating components, services, directives, pipes, guards, or resolvers
- Implementing reactivity with Angular Signals, `linkedSignal`, or `resource`
- Working with Angular forms (signal forms, reactive forms, or template-driven)
- Setting up dependency injection, routing, lazy loading, or route guards
- Adding accessibility (ARIA), animations, or component styling
- Writing or debugging Angular-specific tests (unit, component harness, E2E)
- Configuring Angular CLI tooling or the Angular MCP server

1. Always analyze the project's Angular version before providing guidance, as best practices and available features can vary significantly between versions. If creating a new project with Angular CLI, do not specify a version unless prompted by the user.

2. When generating code, follow Angular's style guide and best practices for maintainability and performance. Use the Angular CLI for scaffolding components, services, directives, pipes, and routes to ensure consistency.

3. Once you finish generating code, run `ng build` to ensure there are no build errors. If there are errors, analyze the error messages and fix them before proceeding. Do not skip this step, as it is critical for ensuring the generated code is correct and functional.

## Creating New Projects

If no guidelines are provided by the user, use these defaults when creating a new Angular project:

1. Use the latest stable version of Angular unless the user specifies otherwise.
2. Prefer Signal Forms for new projects only when the target Angular version supports them.

**Execution Rules for `ng new`:**
When asked to create a new Angular project, you must determine the correct execution command by following these strict steps:

**Step 1: Check for an explicit user version.**

- **IF** the user requests a specific version (e.g., Angular 15), bypass local installations and strictly use `npx`.
- **Command:** `npx @angular/cli@<requested_version> new <project-name>`

**Step 2: Check for an existing Angular installation.**

- **IF** no specific version is requested, run `ng version` in the terminal to check if the Angular CLI is already installed on the system.
- **IF** the command succeeds and returns an installed version, use the local/global installation directly.
- **Command:** `ng new <project-name>`

**Step 3: Fallback to Latest.**

- **IF** no specific version is requested AND the `ng version` command fails (indicating no Angular installation exists), you must use `npx` to fetch the latest version.
- **Command:** `npx @angular/cli@latest new <project-name>`

## Live docs

For authoritative API reference, syntax, best practices, and CLI documentation across all Angular topics, use the [context7 knowledge base](/ponytail/context7) to fetch current `angular.dev` documentation.

## Anti-Patterns

- Using `null` or `undefined` as initial signal form field values — use `''`, `0`, or `[]` instead
- Accessing form field state flags without calling the field first: `form.field.valid()` — use `form.field().valid()`
- Starting new forms with older form APIs when the target Angular version supports Signal Forms
- Setting `min`, `max`, `value`, `disabled`, or `readonly` HTML attributes on `[formField]` inputs — define these as schema rules instead
- Calling `inject()` outside an injection context — use `runInInjectionContext` when needed
- Using `effect()` for derived state that should use `computed()`
- Referencing `$parent.$index` in nested `@for` loops — Angular does not support `$parent`; use `let outerIdx = $index` instead

## Related Skills

- `tdd` — test-driven development workflow applicable to Angular components and services
- `security-review` — security checklist for web applications including Angular-specific concerns
- `frontend-patterns` — general frontend patterns for context on React/Next.js approaches
