# review-pr Reference

Static lookup tables for kbg:review-pr skill. Loaded on-demand when the skill is invoked; not part of the session prefix cache.

---

## Review Aspects Reference

| Aspect arg | Routes to | Notes |
|---|---|---|
| `code` | `code-reviewer` ONLY | general quality pass, doesn't include test / security / etc |
| `tests` | `pr-test-analyzer` | only if test files changed (Phase 3 condition) |
| `comments` | `comment-analyzer` | only if docs/comments added |
| `errors` | `silent-failure-hunter` | only if error handling changed |
| `security` | `security-reviewer` | only if auth/secrets/input touched |
| `types` | `type-design-analyzer` | only if types/interfaces/DTOs/schemas/models changed |
| `ux` | `ux-reviewer` | only if user-facing UI/components/flows changed |
| `simplify` | NOT a reviewer | invoke `backend-engineer` (clarity-only scope) separately after review decisions land (Phase 7 next-step) — see `kbg:progressive-refine` Pass 2 |
| `all` | every applicable agent per Phase 3 routing | default if no aspect arg |

## Agent Descriptions

One-line orientation; **see kbg:inventory for current frontmatter descriptions and the agent file (plugin-delivered or project-local) for full body** (single source of truth — these blurbs intentionally stay terse to avoid drift).

| Agent | Specialty |
|---|---|
| `comment-analyzer` | Comment accuracy + rot detection + doc completeness |
| `pr-test-analyzer` | Behavioral test-coverage gaps (rated 1-10 by criticality, not by line %) |
| `silent-failure-hunter` | Silent failures + broad catches + unjustified fallbacks |
| `security-reviewer` | OWASP + auth + secrets + supply chain — flags with severity, doesn't fix |
| `code-reviewer` | General quality + CLAUDE.md compliance — issues-only at confidence ≥80 |
| `type-design-analyzer` | Type/DTO/schema encapsulation + invariants + API-contract honesty (rated 1-10) |
| `ux-reviewer` | UX friction + cognitive load + WCAG 2.1 AA accessibility + interaction flow |
| `backend-engineer` post-review polish (clarity-only scope, **not** a reviewer) | Clarity/readability refactor without behavior change |

## Tips

- **Run early**: Before creating PR, not after
- **Focus on changes**: Phase 2's pinned window makes this concrete
- **Address Critical first**: Phase 6's tier prioritization is the gate
- **Re-run after fixes**: Verify issues are resolved (new HEAD_SHA = fresh window)
- **Use specific aspects**: Target specific reviewers when you know the concern (e.g., kbg:review-pr errors after touching exception handling)

## Workflow Integration

**Before committing:**
```
1. Write code
2. Run: kbg:review-pr code errors
3. Fix any Critical issues
4. Commit
```

**Before creating PR:**
```
1. Stage all changes
2. Run: kbg:review-pr all
3. Address all Critical and Important findings
4. Run specific reviews again to verify (Phase 2 pins new window)
5. Create PR
```

**After PR feedback:**
```
1. Use /address-review for reviewer threads (not kbg:review-pr — that's for YOUR review of the diff)
2. Make requested changes (delegate bug-shaped to /fix-bug per /address-review Phase 4)
3. Verify issues are resolved
4. Push updates
```

---

## Review Comment Templates (Reviewer → Author)

Loaded when the skill is invoked; not part of the session prefix cache. Use as starting points — adapt to context.

### Structure
Every review comment should contain:
1. **Observation** — what you see (`file:line` reference)
2. **Impact** — why it matters (bug? security? maintainability?)
3. **Recommendation** — concrete fix or alternatives

### Templates by category

**Bug / Correctness**
> This will [fail / behave incorrectly] when [condition] because [mechanism].
> [Concrete fix or reference to similar handling elsewhere].

**Style / Convention**
> Doesn't match [convention] used in [file/scope]. This project uses [pattern]; follow that.

**Architecture / Design**
> [Concern] because [reason]. Consider [alternative A] or [alternative B]. Trade-off: A gives [X] but costs [Y].

**Security**
> [Vulnerability] — [OWASP category if applicable]. Impact: [what goes wrong]. Fix: [concrete recommendation].

**Nit / Optional**
> Optional: [suggestion]. Not blocking.

### Anti-patterns (reviewer)

| Don't write | Why | Write instead |
|---|---|---|
| "Great catch!" / "Good point!" | Performative agreement wastes reader time | Skip ceremony; state observation directly |
| "I think maybe this could be..." | Hedge language signals low confidence | State observation plainly or skip |
| "This is wrong" (without why) | Author can't learn or fix | Add "because..." + concrete alternative |
| "Just do X" | Dismissive; may miss context | "Consider X — here's why it fits..." |

---

## Reply Comment Templates (Author → Reviewer)

Phase 5 of `/address-review` requires every thread gets a reply. Use these as starting points.

### Fixed
```
Fixed in `<short-sha>`: [one-line change summary].
[Optional: reason why this fix is correct / what changed].
```

### Wontfix
```
[Rationale in 1-3 sentences].
This is [intentional / out of scope for this PR / addressed in <other-place>] because [reason].
```

### Clarify
```
[Specific question]. I'm not sure I understand [aspect] — could you clarify [specific thing]?
```

### Out-of-scope
```
Tracked as #<issue-number>. Out of scope for this PR — [reason]. Will pick up in follow-up.
```

### Anti-patterns (author)

- **Performative agreement** — "Great catch!" / "You're absolutely right!" / "Good point, thanks!" violates technical rigor. The sha citation + one-line change summary IS the acknowledgment.
- **Silent push** — pushing fix commits without replying. Reviewer has to re-read the diff to find what changed.
- **Defensive tone** — "Actually..." / "But the spec says..." triggers adversarial loops. State the rationale plainly, cite evidence, move on.
