# matt-harness

The Claude Code harness (`mh@wasikarn`) and its doctrine: what gates deny computationally,
what stays advice, and how it composes third-party plugins instead of duplicating them.

## Language

**Codex** (as mh's docs use the word):
The installed Claude Code plugin `codex@openai-codex` (source repo `openai/codex-plugin-cc`),
which exposes the `/codex:*` commands and wraps the Codex CLI (`@openai/codex`). mh treats it
as a second, independent coding agent — a different model family with different blind spots —
never as a subordinate tool mh drives.
_Avoid_: "Codex Companion" (the plugin's own internal/product name, not mh's term for it);
"the Codex CLI" as a stand-in for the whole plugin (the CLI is only the binary the plugin
shells out to; the plugin also owns job state, the review gate, and the `/codex:*` surface).

**Review gate**:
Codex's own optional Stop-time hook (config key `stopReviewGate`, off by default, toggled by
`/codex:setup --enable-review-gate`). When on, it runs a Codex review and can block a Claude
Code session from ending. The Stop hook itself is registered unconditionally whenever the
plugin is enabled — the toggle controls what it *does*, not whether it's *wired in*; off, it
reads local state and returns without spawning anything.
_Avoid_: confusing this with mh's own gates (`gate:*` in `hooks/hooks.json`). Those deny or ask
on a tool call before it runs, by a computational rule. The review gate blocks a Stop after
the fact, by an LLM's judgment call — exactly the shape mh's operating model keeps out of the
deny/ask set. mh's constraint is that this stays off.

**Pairing** (Codex pairing):
Installing and enabling Codex as its own independent plugin alongside mh, routed to by name
for a second opinion from a different model family. Not a wrapper, mirror, or orchestration
layer — mh creates no surface whose only job is to call Codex.
_Avoid_: "integration," which implies code-level coupling mh deliberately avoids; "orchestration,"
which implies mh sequences or supervises Codex's work.
