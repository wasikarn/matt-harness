# Haiku decision calls

Pattern for a skill that needs a fast, cheap, schema-locked yes/no or pick-one decision mid-flow,
without dispatching a full adversarial-review subagent. Not wired into any skill or gate yet —
this is a reference for a future author to cite, the same role `spawn-brief.md` plays for
subagent dispatch shape. Background and the "should mh build a Jev clone" question this answers:
`docs/research/haiku-jev-decision-primitive-2026-09-18.md`.

## The pattern

Dispatch a fresh Agent with `model: "haiku"`, forcing a single tool call with a narrow enum
`input_schema`, `strict: true`, no `thinking`, and a tight `max_tokens`:

```json
{
  "model": "claude-haiku-4-5-20251001",
  "max_tokens": 64,
  "tool_choice": {"type": "tool", "name": "answer"},
  "tools": [{
    "name": "answer",
    "strict": true,
    "input_schema": {
      "type": "object",
      "properties": {"choice": {"type": "string", "enum": ["a", "b", "c"]}},
      "required": ["choice"]
    }
  }]
}
```

`strict: true` turns on grammar-constrained sampling, which guarantees the tool `input` matches
the schema — the same class of structural guarantee Jev's `Choice`/`Noul` primitives claim, via a
different mechanism (constrained decoding on a still-autoregressive model, not a non-autoregressive
head). It's faster and cheaper than an open-ended call on the same task, for the ordinary reason a
short forced answer costs less than a free-form one — not because it skips attending over the
input context.

## Two hard caveats

- **Thinking must stay off.** `tool_choice: {type: "tool", ...}` fails if manual extended thinking
  (`thinking: {type: "enabled"}`) is set. Haiku defaults to thinking off; don't turn it on for a
  forced-tool call.
- **No confidence field.** The Messages API has no logprobs or token-probability field anywhere.
  A "confidence" number the model writes into its own JSON output is self-reported, not measured —
  weaker than even Jev's own confidence field. Per Rule 14, don't manufacture one; omit it or
  return **ข้อมูลไม่เพียงพอ**.

## When not to use this

For an adversarial audit, multi-page brief, or anything needing `findings[]`-shaped output, use
the existing `codex exec --output-schema` / Claude-fallback contract pattern instead
(`docs/reference/codex-integration-map.md`, `docs/reference/spawn-brief.md`) — this pattern is for
a single cheap in-flow decision, not a review pass.

## Sources

- [Define tools — Forcing tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools#forcing-tool-use) — `tool_choice` types, manual-extended-thinking restriction
- [Strict tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/strict-tool-use) — grammar-constrained sampling guarantee
- [Claude Haiku 4.5 model page](https://platform.claude.com/docs/en/models/haiku-4-5/overview) — model ID `claude-haiku-4-5-20251001`, manual extended thinking default
- [Messages API reference](https://platform.claude.com/docs/en/api/messages) — no logprobs/token-probability field exists
- [Pricing](https://platform.claude.com/docs/en/about-claude/pricing) — Haiku 4.5 $1/$5 per MTok in/out
- `docs/research/haiku-jev-decision-primitive-2026-09-18.md` — full feasibility analysis and design options
