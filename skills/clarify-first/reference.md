# clarify-first Reference

On-demand detail for `clarify-first` skill. Loaded when the agent needs templates, anti-pattern checks, or Thai-register guidance.

---

## The 4 Rules (with Thai Register Adaptations)

### 1. Be Specific

**Good**: "Which metric, under what load, compared to what baseline?"
**Bad**: "What about performance?"

**Thai adaptation**: Use concrete nouns and bounded ranges. Avoid broad generalities that force the user to narrow the scope for you. If the user wrote "ระบบช้า" (system is slow), ask: "slow ที่ endpoint ไหน ณ throughput เท่าไหร่" — not "ทำไมช้า".

### 2. Remove Jargon

**Good**: "Which config value controls the timeout?"
**Bad**: "What's the TTL for the circuit breaker?"

**Thai adaptation**: Strip English technical abbreviations unless the user already used them. Match the user's vocabulary level. If they said "API ค้าง" don't escalate to "connection pool exhaustion" — ask about "การเชื่อมต่อที่ไม่ปิด" instead.

### 3. Avoid Leading or Double-Barreled Questions

**Good**: "Should this be a narrow patch or a reusable component?" with trade-offs explained.
**Bad**: "Don't you think we should just use X?" or "What language and what framework should we use?"

**Thai adaptation**: Never use "ทำไม" chains (sounds accusatory). Replace with "อะไรเป็นจุดเริ่มต้น..." or "อย่างไร...". Never imply the user made an error — frame as shared exploration: "ช่วยเล่าให้ฟังหน่อยครับว่า..." not "Explain your reasoning."

### 4. Provide Context

**Good**: "Based on the codebase, this appears to be a NestJS monorepo with existing auth middleware. Should the new endpoint reuse the current JWT guard or require a separate scope check?"
**Bad**: "What should I do?"

**Thai adaptation**: State what you've already read/done before asking. Thai users extend kreng-jai to AI — they may say "ไม่เป็นไร" (it's nothing) when they actually need help. If you detect deferral, gently re-offer with added context rather than accepting the surface refusal.

---

## Anti-Patterns

| Anti-Pattern | What it looks like | Fix |
|---|---|---|
| **Lazy question** | Asking something the codebase already answers | Read one more file before asking |
| **Advice Monster** | "Don't you think you should just use X?" | Replace with neutrally-framed options + trade-offs |
| **Socratic Trap** | Hidden predetermined answer; asking to confirm, not discover | State your hypothesis openly; ask what would disprove it |
| **Why hammer** | Repeated "ทำไม" (Thai) or "why" (English) | Map to "What led to..." or "How did this come about..." |
| **Multi-barrage** | Stacking 3+ questions in one breath | One question at a time; allow space between turns |
| **Superiority display** | Questions that imply Claude already knows the answer | Ask from curiosity, not examination |
| **Kreng-jai blind spot** | Accepting "ไม่เป็นไร" / "if it's not too much trouble" at face value | Probe gently once more with added context |
| **Silent default** | Proceeding with sequential mode without asking | Always gate when the choice has consequences |
| **Sophistication signaling** | User answers in buzzwords — "scalable", "modern", "clean", "best practice" — to look credible rather than state the real need | Unmask the goal: "If you didn't have to justify it to anyone, what would you actually want?" — probe the underlying need, not the performative answer |

---

## Quick Reference: Question Templates

### Requirement Elicitation (5W1H)
- **Who** will use this / be affected by this?
- **What** exactly should the system do when [edge case]?
- **When** does this need to run — real-time, batch, or triggered?
- **Where** in the codebase should this live?
- **Why** is this needed — what problem does it solve?
- **How** do we know it's working — what's the success metric?

### Debugging Clarification (Blameless)
- "What are the exact steps to make the failure happen?"
- "What did you observe that makes you think [component] is the cause?"
- "What would have to be true for [hypothesis] to explain the symptom?"
- "If we had to stop investigating now, what's the safest mitigation?"

### Scope / Strategy Confirmation
- "The request covers [A] and [B]. These touch different subsystems. Should I treat them as one feature or two?"
- "My reading of the codebase suggests [existing pattern X]. Should I follow it or is there a reason to deviate?"
- **When the user says "refactor" without specifying depth**: Analyze the scope of change — is this a narrow patch, an extraction into a reusable module, or a full rewrite? State your read of the current code's complexity and recommend the smallest viable scope that satisfies the request. Do **not** pivot to meta-questions (e.g., "switch repo?") unless the codebase genuinely contains zero relevant code.

### Thai-Register Softening
- "ขออนุญาตถามหน่อยครับ — [specific question]" (May I ask — ...)
- "ช่วยเล่าให้ฟังหน่อยครับว่า [specific topic]" (Please share about ...)
- "ถ้าไม่ลำบากเกินไป อยากทราบว่า [specific detail]" (If it's not too much trouble, I'd like to know ...)
- "เราลองมองย้อนกลับไปดูว่าอะไรเป็นจุดเริ่มต้นของ [issue] ครับ" (Let's look back at what led to ...)

---

## Integration Notes

- **Auto Mode v2.1.146+**: Explicit `AskUserQuestion` flows are NOT suppressed by Auto Mode. This skill is safe to invoke even when Auto Mode is active.
- **Sub-agents**: Sub-agents CANNOT use `AskUserQuestion`. If a sub-agent encounters ambiguity, it should return its analysis + recommendation to the main Claude, which then runs the gate.
- **Session budget**: Each question gate costs ~200–500 tokens. A workflow with 3 well-placed gates is cheaper than one wrong assumption that requires a full redo.
- **Overlap guard**: If the user has already invoked `kbg:decide` probe mode on the same topic, reuse its output in the Analyze step — don't re-derive.
