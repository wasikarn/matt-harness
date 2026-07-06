# review-pr Reference

Static lookup tables for kbg:review-pr skill. Loaded on-demand when the skill is invoked; not part of the session prefix cache.

---

## Review Aspects Reference

| Aspect arg | Routes to | Notes |
|---|---|---|
| `code` | `code-reviewer` (general-quality lens) ONLY | general quality pass, doesn't include test / security / etc |
| `tests` | `code-reviewer` (behavioral test-coverage lens) | only if test files changed (Phase 3 condition) |
| `comments` | `code-reviewer` (comment-accuracy lens) | only if docs/comments added |
| `errors` | `silent-failure-hunter` | only if error handling changed |
| `security` | `security-reviewer` | only if auth/secrets/input touched |
| `types` | `code-reviewer` (type-design lens) | only if types/interfaces/DTOs/schemas/models changed |
| `ux` | `code-reviewer` (UX/a11y lens) | only if user-facing UI/components/flows changed |
| `simplify` | NOT a reviewer | run native `/simplify` (clarity-only) separately after review decisions land (Phase 7 next-step) |
| `all` | every applicable agent per Phase 3 routing | default if no aspect arg |

## Fowler Smell Baseline

Always-on background for the `code` aspect's general-quality lens — alongside whatever CLAUDE.md or repo docs already specify, not a new axis. Two binding rules: a documented repo standard always overrides the baseline; every smell below is a judgement call ("possible Feature Envy"), never a hard violation. Skip anything tooling already enforces.

| Smell | What it is | Fix |
|---|---|---|
| Mysterious Name | Name doesn't reveal what it does or holds | Rename; if no honest name comes, the design's murky |
| Duplicated Code | Same logic shape in more than one hunk/file | Extract the shared shape, call it from both |
| Feature Envy | A method reaches into another object's data more than its own | Move the method onto the data it envies |
| Data Clumps | Same fields/params keep travelling together | Bundle into one type, pass that |
| Primitive Obsession | A primitive/string standing in for a domain concept | Give the concept its own small type |
| Repeated Switches | Same switch/if-cascade on the same type recurs | Replace with polymorphism, or one shared map |
| Shotgun Surgery | One logical change forces scattered edits across many files | Gather what changes together into one module |
| Divergent Change | One file/module edited for several unrelated reasons | Split so each module changes for one reason |
| Speculative Generality | Abstraction/params/hooks added for needs the spec doesn't have | Delete it; inline back until a real need shows |
| Message Chains | Long `a.b().c().d()` navigation the caller shouldn't depend on | Hide the walk behind one method on the first object |
| Middle Man | A class/function that mostly just delegates onward | Cut it, call the real target direct |
| Refused Bequest | A subclass/implementer that ignores or overrides most of what it inherits | Drop the inheritance, use composition |

Source: Fowler, *Refactoring* ch.3.

## Agent Descriptions

One-line orientation; **see kbg:inventory for current frontmatter descriptions and the agent file (plugin-delivered or project-local) for full body** (single source of truth — these blurbs intentionally stay terse to avoid drift).

| Agent | Specialty |
|---|---|
| `silent-failure-hunter` | Silent failures + broad catches + unjustified fallbacks |
| `security-reviewer` | OWASP + auth + secrets + supply chain — flags with severity, doesn't fix |
| `code-reviewer` | General quality + CLAUDE.md compliance — issues-only at confidence ≥80. Also carries the **comment-accuracy lens** (comment accuracy + rot + doc completeness), the **type-design lens** (type/DTO/schema encapsulation + invariants + illegal-states-unrepresentable), the **behavioral test-coverage lens** (test gaps by criticality, not line %), and the **UX/a11y lens** (interaction flow + WCAG basics) |
| native `/simplify` (post-review polish, **not** a reviewer) | Clarity/readability refactor without behavior change |

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
