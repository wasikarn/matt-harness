# Task Handoff Template — what to give Claude Code before it starts

A fill-in prompt skeleton for the human side of a Claude Code task. Use it **before** you send a task to Claude Code so the input is sufficient on the first pass — fewer corrections, fewer "I forgot to mention…" rounds, less context pollution.

Grounded in three Anthropic docs (see § Source mapping at the end):
- `code.claude.com/docs/en/best-practices.md` — verify-its-work, scope, reference-existing-patterns, describe-the-symptom, interview-me, self-contained spec, failure patterns.
- `code.claude.com/docs/en/prompt-library.md` — the 6 patterns: outcome-not-steps, self-check, reference, measurable target, artifact, format.
- `platform.claude.com/.../claude-prompting-best-practices.md` — add-context/motivation, XML structure, the golden-rule colleague test.

---

## When to use it (and when not)

| Situation | Use |
|---|---|
| Multi-file change, unfamiliar code, uncertain approach, or a feature spec | **Full template** below |
| One-line fix, clear scope, you could describe the diff in one sentence | **Skip it** — a single precise sentence beats a filled scaffold (best-practices: "if you could describe the diff in one sentence, skip the plan") |
| You're not sure what's hard yet | Send only `<task>` + "interview me for the rest using AskUserQuestion" — let Claude surface the edge cases, then fill the template with its questions answered |

The template's job is to front-load the context Claude can't infer. If a field is already obvious from the code or CLAUDE.md, leave it empty — don't pad.

---

## The template

Copy and fill. Empty fields are fine; a missing `<done-when>` is the one field that actually costs you.

```text
<task>
[One sentence: the OUTCOME you want, not the steps. Name what you want;
let Claude find the files. "add rate limiting to the public API and make
sure existing tests still pass", not "open src/api.ts and add a
RateLimiter class and…"]
</task>

<context>
[Why this matters / the situation. "users report login fails after
session timeout, likely in token refresh" — the motivation lets Claude
generalize beyond the literal instruction and skip dead-end fixes.]
</context>

<scope>
- In scope:   [files / areas / which scenario]
- Out of scope: [explicitly name what NOT to touch — prevents over-eager
                edits and the "infinite exploration" failure mode]
- Target file(s) if known: @path/to/file   (use @ so Claude reads the
                source, not your description of it)
</scope>

<reference>
[An existing file / test / pattern to match. "follow the same layout as
the profile page" / "HotDogWidget.php is a good example — match its
pattern" — keeps new code consistent with what's already there.]
</reference>

<artifacts>
[Paste directly, don't describe: error logs, stack traces, screenshots,
plan output. Or @file references. "why is the build failing? @build.log"
beats paraphrasing the error.]
</artifacts>

<done-when>
[The CHECK Claude can run itself — a test, a build exit code, a linter,
a diff against a fixture, a screenshot to compare. Plus a measurable
target when the goal is perf/coverage. "write a failing test that
reproduces the issue, then fix it; run the suite and confirm green" /
"get the bundle size under 200KB and show me what you removed." This is
the field that turns a watched session into a walk-away session.]
</done-when>

<constraints>
[Don'ts and conventions — ONLY rules that differ from defaults or that
Claude can't infer from the code. "avoid mocks" / "no new libraries
beyond what's already used" / "don't suppress the error — address the
root cause" / "typecheck when done". List rules Claude already follows
and they become noise it learns to ignore.]
</constraints>

<output>
[How you want the answer: format, length, audience. "explain how the
payment retry logic works as an HTML page with a diagram, then open it"
/ "return OK or FAIL" / "list findings that affect correctness, not
style preferences".]
</output>

<edge-cases>
[Gotchas you already foresee. If you can't name any, write
"interview me for edge cases first" — Claude will surface them via
AskUserQuestion before coding, which is cheaper than discovering them
after a wrong implementation.]
</edge-cases>
```

---

## Field-by-field — ใส่อะไร และมาจากไหน

| Field | ใส่อะไร | Why / source |
|---|---|---|
| `<task>` | ผลลัพธ์ 1 บรรทัด ไม่ใช่ขั้นตอน | Prompt library pattern 1 (outcome, not steps); best-practices "describe the symptom" |
| `<context>` | เหตุผล/สถานการณ์ ทำไมต้องทำ | Prompting best-practices: "add context to improve performance" — Claude generalizes from the *why* |
| `<scope>` | file เข้า/ออก scope + `@`-refs | Best-practices "scope the task" + "point to sources"; self-contained spec rule: name what's out of scope |
| `<reference>` | pattern/file ที่มีอยู่ให้เลียนแบบ | Prompt library pattern 3; best-practices "reference existing patterns" |
| `<artifacts>` | วาง error/log/screenshot ตรงๆ หรือ `@file` | Prompt library pattern 5 (give it the artifact); best-practices "provide rich content" |
| `<done-when>` | check ที่ Claude รันเองได้ + เป้า measurable | Best-practices "give Claude a way to verify its work"; prompt library patterns 2 (self-check) & 4 (measurable target) |
| `<constraints>` | เฉพาะ rule ที่ต่างจาก default | Best-practices "scope the task"; CLAUDE.md pruning test ("would removing this cause mistakes? if not, cut it") |
| `<output>` | format/ความยาว/ผู้รับ | Prompt library pattern 6 (say how you want the answer) |
| `<edge-cases>` | gotcha ที่นึกได้ หรือ "interview me" | Best-practices "let Claude interview you" — surfaces hard parts before they cost a wrong implementation |

---

## Pre-send checklist (the golden rule)

Prompting best-practices' golden rule: **show your filled prompt to a colleague with minimal context on the task and ask them to follow it. If they'd be confused, Claude will be too.** Concretely, before sending, can a context-poor reader answer:

1. **What does "done" look like?** — is there a check in `<done-when>`?
2. **Which files are in / out of scope?** — is `<scope>` filled?
3. **Do they have the actual artifact** (error/log/screenshot), or only your description of it?
4. **Do they know what pattern to follow?** — is `<reference>` pointed at one?

Any "no" → fill that field before sending. The most expensive "no" is #1 (no check) — that makes you the verification loop.

---

## Worked example

**Before** (vague — you become the verification loop):
```text
fix the login bug
```

**After** (filled template — Claude can close the loop itself):
```text
<task>
Fix the login failure that happens after a session timeout.
</task>

<context>
Users report login fails after session timeout. Suspect the token
refresh path. This is production-impacting, so root cause only — no
suppressing the error to make it go away.
</context>

<scope>
- In scope: src/auth/ token-refresh flow, especially @src/auth/refresh.ts
- Out of scope: the login UI, the session store rewrite (separate task)
</scope>

<reference>
Match the error-handling pattern already in @src/auth/login.ts
(try/refresh/rethrow, not silent catch).
</reference>

<artifacts>
User-reported error: "AuthError: expired token at refresh.ts:42"
Stack trace: @logs/auth-fail.log
</artifacts>

<done-when>
Write a failing test that reproduces the timeout-then-refresh failure,
then fix it. Run `npm test -- src/auth` and confirm green. Address the
root cause — don't catch and swallow.
</done-when>

<constraints>
- No new dependencies.
- Don't touch the session store (out of scope).
- Typecheck when done: `npm run typecheck`.
</constraints>

<output>
One-paragraph summary of the root cause + the test you added, then the
diff.
</output>
<edge-cases>
Clock skew between client and server token expiry; concurrent refresh
requests for the same user.
</edge-cases>
```

---

## Minimal version (small / clear tasks only)

When scope is obvious and the fix is small, two fields are enough:
```text
<task>[outcome in one sentence]</task>
<done-when>[the check Claude can run]</done-when>
```

---

## Failure patterns this template prevents

From best-practices' "common failure patterns" — each maps to a field:

- **Kitchen-sink session** (unrelated tasks in one context) → `<scope>` out-of-scope + `/clear` between tasks.
- **Correcting over and over** (context polluted with failed approaches) → a better initial prompt (this template) beats a long correction session; after 2 failed corrections, `/clear` and re-send a filled template.
- **Trust-then-verify gap** (plausible impl that misses edge cases) → `<done-when>` forces a check; "if you can't verify it, don't ship it."
- **Infinite exploration** (unscoped "investigate" reads hundreds of files) → `<scope>` narrows it; use subagents for research so exploration doesn't fill your main context.
- **Over-specified constraints** (noise drowns the real rules) → `<constraints>` lists only non-default rules; the rest Claude infers or reads from CLAUDE.md.

---

## Source mapping (traceability)

| Template element | Source doc | Specific anchor |
|---|---|---|
| Outcome-not-steps `<task>` | prompt library | "Describe the outcome, not the steps" |
| `<context>` motivation | prompting best-practices | "Add context to improve performance" |
| `<scope>` + out-of-scope + `@` | best-practices | "Scope the task" / "Point to sources" / self-contained spec "state what is out of scope" |
| `<reference>` | prompt library + best-practices | "Point at a reference" / "Reference existing patterns" |
| `<artifacts>` paste-don't-describe | prompt library + best-practices | "Give it the artifact" / "Provide rich content" (`@`, paste images, pipe data) |
| `<done-when>` check + measurable target | best-practices + prompt library | "Give Claude a way to verify its work" / "State the measurable target" / "Give it a way to check its own work" |
| `<constraints>` non-default-only | best-practices + CLAUDE.md doctrine | "Scope the task" / CLAUDE.md pruning test "would removing this cause mistakes?" |
| `<output>` format | prompt library | "Say how you want the answer" |
| `<edge-cases>` + interview-me | best-practices | "Let Claude interview you" (AskUserQuestion, dig into hard parts) |
| XML-tag structure | prompting best-practices | "Structure prompts with XML tags" (`<instructions>`, `<context>`, `<input>`) |
| Golden-rule colleague test | prompting best-practices | "Show your prompt to a colleague with minimal context…" |
| Failure-patterns section | best-practices | "Avoid common failure patterns" (kitchen sink, correcting over and over, trust-then-verify, infinite exploration, over-specified CLAUDE.md) |
| Reviewer "gaps not style" caveat | best-practices | "flag only gaps that affect correctness… treat the rest as optional" (use in `<output>` for review tasks) |