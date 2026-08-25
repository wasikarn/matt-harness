# Comment Templates

Review-comment and reply-comment shapes for `mh:address-review` — the single source SKILL.md Phases 4–5 point at.

---

## Review Comment Templates (Reviewer → Author)

Loaded when the skill is invoked; not part of the session prefix cache. Use as starting points — adapt to context.

### Structure
Every review comment should contain:
1. **Observation** — what you see (`file:line` reference)
2. **Impact** — why it matters (bug? security? maintainability?)
3. **Recommendation** — concrete fix or alternatives
4. **Falsifying fact** (judgment calls only — skip on objective bugs) — the one fact that would
   change this recommendation, e.g. "if this endpoint has no external caller, this isn't a
   breaking change"

### Code citation
- **Terminal/local review output, and line-level GitHub comments** — the `gh api …/pulls/<n>/reviews`
  path anchors each comment at `path`+`line` already, so a bare `file:line` is enough; a permalink there is redundant.
- **Summary-only comments and any cross-reference to *other* code** (a line the comment is not anchored
  to — e.g. "similar handling exists at …") — cite a **full-SHA permalink** so it renders and links:
  `https://github.com/<owner>/<repo>/blob/<full-sha>/<path>#L<start>-L<end>`, centered with ≥1 line of context.
  Two gotchas (both silently break the link): a bare `file:line` does **not** hyperlink in posted markdown,
  and `blob/$(git rev-parse HEAD)/…` does **not** render — the shell isn't evaluated in a posted comment, so
  resolve `git rev-parse HEAD` first and paste the literal SHA. (Convention: Anthropic's official `code-review` plugin.)

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

Phase 5 of `mh:address-review` requires every thread gets a reply. Use these as starting points.

### Fixed
```
Fixed in `<short-sha>`: [one-line change summary].
[Optional: reason why this fix is correct / what changed].
```

### Wontfix
```
[Rationale in 1-3 sentences].
This is [intentional / out of scope for this PR / addressed in <other-place>] because [reason].
[Revisit if: <the fact or event that would reopen this — even a permanent design call names
what would change it>].
```

### Clarify
```
[Specific question]. I'm not sure I understand [aspect] — could you clarify [specific thing]?
```

### Out-of-scope
```
Tracked as #<issue-number>. Out of scope for this PR — [reason]. Will pick up in follow-up.
```

### Blending a sha into Wontfix / Clarify

The Wontfix and Clarify shapes aren't mutually exclusive with citing a sha. If a commit landed and genuinely fixed part of the concern before the cluster stalled or got reclassified (e.g. `mh:address-review` Phase 4 step 3's one-retry-then-stop), lead with the Fixed template's sha + one-line summary, then follow with the full Wontfix or Clarify body — don't drop the citation, and don't abbreviate the body, just because the category ended up Wontfix/Clarify instead of Fixed:
```
Fixed in `<short-sha>`: [what that commit changed].
[Rationale in 1-3 sentences].
This is [intentional / out of scope for this PR / addressed in <other-place>] because [reason].
[Revisit if: <the fact or event that would reopen this>].
```
(Clarify blends the same way — swap the "This is... because..." and "Revisit if" lines for
Clarify's `[Specific question]. I'm not sure I understand [aspect]...` line.)

### Anti-patterns (author)

- **Performative agreement** — "Great catch!" / "You're absolutely right!" / "Good point, thanks!" violates technical rigor. The sha citation + one-line change summary IS the acknowledgment.
- **Silent push** — pushing fix commits without replying. Reviewer has to re-read the diff to find what changed.
- **Defensive tone** — "Actually..." / "But the spec says..." triggers adversarial loops. State the rationale plainly, cite evidence, move on.
