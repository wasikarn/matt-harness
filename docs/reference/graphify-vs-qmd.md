# graphify: architecture/relationship questions, not a qmd replacement

Moved out of the root `CLAUDE.md` 2026-09-03.

`graphify` (`~/.claude/skills/graphify/SKILL.md`, installed separately — not bundled with
this plugin) builds a knowledge graph from a corpus via AST + LLM semantic extraction, then
answers structural questions with `graphify query`/`path`/`explain`: who calls what, how
concept X connects to file Y, what code enforces a given doctrine. Head-to-head testing
against `qmd` on this repo (2026-08-31, 5-agent drill-down) found the two complementary, not
substitutes: qmd wins "why"/causal/historical questions (it retrieves prose that already
states the reasoning) and anything touching `llm-wiki` or the memory store, which graphify's
graph never covers; graphify wins "where does X live in code and what enforces it" —
extraction labels double as direct structural answers, uniquely bridging docs to code that
qmd's snippet search can't. Neither is a live index: qmd needs a manual `qmd update`/`embed`;
graphify needs a full or `--update` rebuild that dispatches LLM subagents for any changed
doc/paper/image — this repo's actual commit cadence is ~27 doc-type file changes/day, so
keeping the graph current recurs a real per-day token cost, not a one-time build.

**Gotcha:** if `graphify-out/graph.json` is missing, the next `/graphify` invocation
silently falls through to a full corpus rebuild instead of answering from cache — this
session's first full run cost ~4.6M output tokens across 31 parallel subagents (the
platform's 10-concurrent-agent cap forced 4 dispatch waves). Check the file exists before
invoking `/graphify` expecting a cheap query.
