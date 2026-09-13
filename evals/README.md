# Review-agent and skill evals

Twenty-nine cases in Claude Code's native `claude plugin eval` layout. Twelve cover the six review
agents, one planted-defect case and one clean control per agent, the same fires/silent pairing
`tests/skills/harness-audit/known-bad/` uses for audit checks. Each case is
`prompt.md` (the ask: an agent case dispatches by `subagent_type`, a skill case invokes by `skill:`), `case.yaml` (a
`scaffold_script` that writes the fixture into the throwaway workspace), and `graders/`:

| grader | type | what it proves |
|---|---|---|
| `agent-fired.md` | `tool_used: Agent` | the session dispatched the agent instead of reviewing inline |
| `contract.md` | `regex` | the report ends in the agent's documented Output Format |
| `finding.md` / `clean.md` | `regex` | the planted defect was found at its file, or the clean control got the clean verdict |
| `criteria.md` | `llm` | the finding is the right one, sized right, with no manufactured extras |

Five for the `tech-humanize` skill (tag `tech-humanize`): three planted cases (English prose,
Thai standup, Thai UI copy), a clean human-written control that must survive lightly edited, and a file-input
case that proves the prose-only constraint (frontmatter and code block byte-identical, graded on
the file's contents). Their `skill-fired.md` is `tool_used: Skill`; their regex graders assert a
planted tell is absent (`not_contains`) or a source specific is kept (`contains`), and the loader
test proves each pattern against the scaffolded fixture.

Two for `post-mortem` (tag `post-mortem`): a complete case whose repo carries the fix commit and
regression test, graded on all 11 sections in order, no hedging, a Rule 4 failure class, and an
LLM rubric for the checklist and anchoring; and a missing-input case that withholds the
validation input and must get a question, not a draft. The skill is user-invoked
(`disable-model-invocation`), so `prompt.md` opens with `/mh:post-mortem` and `skill-loaded.md`
is a `trace` regex on the skill's own text rather than `tool_used: Skill`. Two runner facts are
undocumented and the first live run settles both: whether a slash command in `prompt.md` is
expanded, and whether `target: trace` is accepted (these are the only two graders using it).

Two for `harness-audit` (tag `harness-audit`): a planted fleet with two CRITs (skill name
mismatch, missing `tools:` grant) that the session must fix and confirm with a second run
(`audit-reran.md` is `tool_used: Bash`, min 2; file graders check the fix landed in the named
file), and a clean control that must get no edits (`no-edits.md` is `tool_used: Edit`, max 0; `max`
is this suite's first use of the key and unverified against the runner, so `fleet-unchanged.md`
proves the same thing on the file's bytes).
The scaffolded repo is its own plugin cache (`--plugin-cache .`). Bash is not granted by
default: run these with `--allow-tools Bash` (the prompt frontmatter also lists it).
Two for `ideate` (tag `ideate`): a full run on an open design problem, bounded on Agent calls
(`fanout.md`, `tool_used: Agent` min 6 max 8: 8 on the host path, 6 when the critic deepens) and
graded on the rendered output shape (score chips, ★ pick, provocation line); the isolation
invariant and wave shape are not observable from these graders; and an abort control, a
"quick"/"canonical" question that must fail the pre-flight gate and get a direct answer with no
Agent call at all (`no-fanout.md`, max 0).

Two for `memory-lint` (tag `memory-lint`): a planted store with one repairable finding per
detector class (typo'd wikilink, stale pointer, unindexed unreachable file) that the session must
fix at the cause and confirm with a second run (`lint-reran.md` is `tool_used: Bash`, min 2; file
graders prove the link was corrected not deleted, the stale pointer removed not satisfied by a new
file, and the unindexed file indexed), and a clean control that must receive no Edit or Write (`store-unchanged.md` proves the index bytes as well).
Bash is not granted by default: run these with `--allow-tools Bash` (the prompt frontmatter lists
it too).

Two for `deep-audit` (tag `deep-audit`): the scaffold is a small git history that is the
"session" under audit. In the planted case the second commit and `NOTES.md` claim a zero-total
guard and a regression test; the commit's diff is a docstring and the suite has no zero-total
case, so the re-run is green with one test and the claim is false on the diff. The case grades
the audit's process (git-derived scope, rubric, checker dispatch, test-first fix, re-score), not
detection difficulty. The clean case makes the same claims truthfully and must come out
byte-identical. Graders check the skill and a checker agent fired, git and the test runner ran
(`tool_used: Bash` anchored on the command), the fix and its test landed in the named files, and
the report opens with the Final Verdict line. Needs `--allow-tools Bash,Edit,Write`.

Two for `cost-report` (tag `cost-report`): a planted log with a session whose two rows must
collapse to the newer one (latest row per key, then sum: $10, where a hand sum gives $15) and one
legacy-era row that makes the script print a `note:` line the read-back must carry; and a
not-set-up control with no log, which must relay the script's "Cost tracker not set up" line,
quote no dollar figure, and create no log (`no-log-created.md` is `tool_used: Bash` max 0 on a
redirect into `costs.jsonl`; Write and Edit are not granted). The prompt points the script at the
workspace log with `MH_COSTS_FILE`, since the sandbox HOME is fresh and case `env` keys must be
`EVAL_*`. Needs `--allow-tools Bash`.

Six for `handoff` (tag `handoff`): plain `prompt.md` + `graders/` cases, no `case.yaml` — this
skill needs no fixture files, so scaffolding wasn't worth adding. Note for future suites:
`context.scaffold_script` must be a relative path to an external `.sh` file in the case dir (e.g.
`scaffold_script: scaffold.sh`); inline YAML block content (the shape every other suite here
predates this and uses) is mis-parsed as a literal path under the installed CLI and fails to load
— confirmed on `post-mortem`, not `handoff`-specific. The other suites in this file haven't been
converted to the file-path form yet. Five fire
cases (clean finish, mixed done/blocked/not-started progress, a live-looking secret that must be
redacted from the persisted doc, a currently-failing named test, and a sparse session that must
mark unknown items "Unknown" rather than invent) plus one should-NOT-fire case: a plain-English
"save my progress" ask with no `/mh:handoff`, which must not freelance a file and should point to
the command. Every fire case's prompt ends with a line telling the model to treat the narrated
session as ground truth rather than re-verifying the sandbox's (empty) filesystem against it —
without that line, a careful model notices the mismatch and the content-quality graders misfire.
The skill's own publish mechanism (`$HOME/.claude/state/mh-handoffs/...`) is outside the sandbox's
writable scope and every attempt there is denied deterministically, every run — graders don't
require a successful `Write`/publish, only that the model attempted the documented steps
(`attempted-staging.md`, `tool_used: Bash`) and that the six-item content is present and honest
wherever it lands (Write input or the final message), never claiming false success. `mh`'s
manifest sets `defaultEnabled: false`; the eval sandbox doesn't inherit the operator's own
enablement override, so the with-arm silently runs without the plugin unless `defaultEnabled` is
temporarily flipped to `true` in `.claude-plugin/plugin.json` for the run and reverted after.

Six for `code-architect` (tag `code-architect`, agent not a skill — dispatched via the `Agent`
tool with `subagent_type: "mh:code-architect"`, not a `disable-model-invocation` slash command).
Natural routing into this agent never fires on its own for a well-worded architecture request —
the top-level model just solves it inline, since it has the same read tools — so every fire-case
prompt explicitly instructs dispatch; that shifts what's measured from "does routing pick this
agent" to "does its process beat a generic fallback," which is what these cases actually test.
Five fire cases, each targeting one of the agent's own specific, checkable claims against a small
scaffolded fixture repo (comments that would spoon-feed the answer are deliberately absent from
the fixtures): a layered repo where the blueprint must not have the domain layer import infra
(`layer-direction`); a closest-shaped existing analog that itself violates layer direction, which
the blueprint must recognize and reject rather than copy (`disqualified-analog`); a single
concrete implementation with a request phrased to invite a speculative plugin interface
(`premature-abstraction`); a codebase with a consistent constructor-injection style the blueprint
must match (`di-style-respect`); and a requirement with a genuine two-reading fork that must be
named as a prominent callout, not silently resolved (`ambiguous-requirement`). Plus one
should-NOT-fire case: a trivial one-line rename, which must be done directly without dispatching
the agent or producing a full blueprint as a substitute (`trivial-no-dispatch`). In the
without-plugin arm, `mh:code-architect` doesn't exist — the model's first dispatch attempt gets
`Agent type 'mh:code-architect' not found. Available agents: ...` and it falls back to the
built-in `Plan` agent. This makes `tool_used: Agent` with `input_match` on the requested
subagent_type a false-positive trap (it matches the failed attempt too, not just a successful
one): `agent-fired.md` is a `regex`/`trace` `not_contains` check on that exact tool-error string
instead. Needs `--allow-tools Bash,Read,Grep,Glob,Agent,Edit` and, like `handoff`, needs
`defaultEnabled: true` temporarily for the with-arm to load the plugin's agents at all.

Six for `performance-optimizer` (tag `performance-optimizer`, agent, same dispatch/ablation
mechanics as `code-architect` — explicit dispatch instruction in every fire-case prompt,
`agent-fired.md` is the tool-error-string regex, `defaultEnabled: true` needed temporarily). Five
fire cases against small runnable JS fixtures with a `bench.js`: a nested-loop O(n²) lookup the
fix must convert to Map/Set and actually benchmark before/after via real `node bench.js` runs, not
invented numbers (`nested-loop-fix`); a function with no measurable bottleneck and no
benchmark/test infra at all, where the report must not assert a specific improvement number it
never actually measured (`cant-measure-refusal`); a deep-clone hot path with a caller that mutates
a nested field on the result, where the fix must stay a real deep clone and not regress to a
`{...obj}` shallow copy — this agent's own reference table names the trap (`shallow-copy-trap`); a
repeated-re-sort-for-min pattern where the reported complexity/impact numbers must match whatever
was actually shipped, not the reference table's heap-queue figure for a technique not built
(`numbers-match-fix`); and a bottleneck ruled architectural in the prompt (parallelization already
tried, hit a third-party vendor's hard rate limit and got the API key banned) where the report
must recognize the real constraint is structural/vendor-side and ask for an explicit decision
rather than shipping a local tweak that implies the volume problem is solved — naming
`backend-architect` by name isn't required, "this needs your decision on X" framing for the real
lever counts (`architectural-handoff`). Plus one should-NOT-fire case: a reported regression with
a before/after (5ms → 2s after a merge) is `mattpocock-skills:diagnosing-bugs`' literal trigger
per this agent's own Scope section, not this agent's — it must take a root-cause diagnostic
approach instead of jumping to speculative optimizations (`regression-routing`). Needs
`--allow-tools Bash,Read,Write,Edit,Grep,Glob,Agent`.

Six for `backend-architect` (tag `backend-architect`, agent, same dispatch/ablation mechanics as
`code-architect`/`performance-optimizer` — explicit dispatch instruction in every fire-case prompt,
`agent-fired.md` is the tool-error-string regex, `defaultEnabled: true` needed temporarily). Five
fire cases against small scaffolded fixtures: a payment-claim worker whose `UPDATE` guards on a
different column (`charge_id IS NULL`) than the one it sets (`status`), letting two concurrent
workers both pass the claim guard and double-charge (`guard-column-bug`); a checkout endpoint that
charges whatever `priceCents` the client sends instead of re-deriving it from the catalog it never
calls (`client-trusted-price`); two service modules writing the same `orders` table directly ahead
of a planned split into separate deployables (`multi-writer-table`); a payment webhook handler with
no dedup/event-id tracking, so retried deliveries resend side effects like the confirmation email
(`no-idempotency-webhook`); and a broad "review the design before launch" request whose fixture
hides a real SQL-injection (string-concatenated query) — the report must notice it, explicitly
defer characterizing exploitability to `/security-review` per the agent's own documented handoff
rule, and not itself construct an attack payload or CVE-style writeup, while a short illustrative
before/after code snippet as part of its own architectural fix doesn't count against it
(`security-handoff`). Plus one should-NOT-fire case: "give me the files/interfaces/build order" for
one new endpoint is file-by-file blueprinting — `code-architect`'s territory per both agents' own
cross-references, not a system-level review — so `backend-architect` must not be dispatched
(`file-blueprint-misroute`). Needs `--allow-tools Bash,Read,Grep,Glob,Agent`.

Six for `ideate-critic` (tag `ideate-critic`, agent — `mh:ideate`'s fresh-context Phase 2 critic,
strict JSON-in/JSON-out contract with `tools: Read, Bash` only, no Edit/Write). `evals/ideate-run/`
already exercises it end-to-end via the full skill; these dispatch it directly with a hand-crafted
Phase-1-style idea envelope to probe its own specific failure modes. Five fire cases, four as plain
`prompt.md` + `graders/` (the envelope is inline JSON in the prompt, no fixture files needed): the
final message must be JSON only, nothing before `{` or after `}`, no markdown fence
(`json-only-contract`); an attractive-looking idea (an in-process cache that silently breaks past
one worker instance) must be flagged with a real `trap` reason and excluded from `shortlist`
(`trap-detection`); three near-identical paraphrases of the same read-through-cache mechanism from
three different frames must land in one cluster with `frameCount` 3, not split by surface wording
— two earlier fixture attempts using genuinely-distinguishable ideas kept getting correctly
re-split by the agent's own sharp reasoning before this near-paraphrase design finally worked
(`cluster-by-angle`); and `shortlistReasons`/`nonObviousPickReason`/`confidence.reason` must be
idea-specific arguments, not restated score numbers, on an idea list close enough in appeal to
tempt generic filler (`shortlist-reasons-specific`). The fifth fire case needs a `case.yaml` +
`scaffold.sh`: `total`/`shortlist`/`runnerUp`/`nonObviousPick` must match `rank.py`'s own Bash
stdout verbatim, never hand-adjusted (`rank-verbatim`) — needs `--allow-tools Bash,Read,Agent`.
Plus one should-NOT-fire case: `mh:ideate-critic`'s own description rules out code/security review
— a request to review a fixture with a real SQL-injection bug must not dispatch it
(`security-review-misroute`) — needs `--allow-tools Bash,Read,Grep,Glob,Agent`.

**A previously-invisible defect, found and fixed while calibrating `ideate-critic`:** the actual
`claude plugin eval` CLI only accepts `context.scaffold_script` as a relative path to an external
`.sh` file — a `scaffold_script: |` inline YAML block is silently mis-parsed as a literal path and
the case fails to load (`path "..." does not exist`), confirmed empirically case-by-case, at $0.00
each (the error fires before any agent turn). This affected 46 of this file's original 65
`case.yaml` files — essentially the entire pre-existing suite predating this file's `handoff`
section — despite `tests/evals/test-eval-cases.sh` reporting all of them `PASS`, because that
script never invokes the real CLI: it only simulates loading by extracting and running the inline
block directly, which the actual CLI cannot do. All 46 have been migrated to external `scaffold.sh`
files (content byte-identical, just relocated); `test-eval-cases.sh` itself has been updated to
read either form, to allow `prompt.md`-only cases (no `case.yaml`) and 2-grader cases with at least
one outcome grader (the two conventions this file's newer suites use), and its hardcoded case count
now reads 76. Spot-checked against the real CLI on both a trivial case (`cost-report-clean`) and a
complex one (`deep-audit-clean`, git-history scaffold) — both now load and run correctly.

Run (needs `plugin eval` early access on the account; 2.1.263 prints "currently in early access"
otherwise):

```bash
claude plugin eval . --scaffold --runs 1 --no-publish
claude plugin eval . --scaffold --tag silent-failure-hunter --runs 1 --no-publish
claude plugin eval . --scaffold --tag harness-audit --allow-tools Bash --runs 1 --no-publish
claude plugin eval . --scaffold --tag memory-lint --allow-tools Bash --runs 1 --no-publish
claude plugin eval . --scaffold --tag ideate --runs 1 --no-publish     # the run case spawns 6-8 agents
claude plugin eval . --scaffold --tag deep-audit --allow-tools Bash,Edit,Write --runs 1 --no-publish
claude plugin eval . --scaffold --tag cost-report --allow-tools Bash --runs 1 --no-publish
# defaultEnabled must be temporarily true in .claude-plugin/plugin.json for these three
claude plugin eval . --tag handoff --allow-tools Bash,Write,Read,Glob,Grep --ablation with-without --no-publish
claude plugin eval . --scaffold --tag code-architect --allow-tools Bash,Read,Grep,Glob,Agent,Edit --ablation with-without --no-publish
claude plugin eval . --scaffold --tag performance-optimizer --allow-tools Bash,Read,Write,Edit,Grep,Glob,Agent --ablation with-without --no-publish
claude plugin eval . --scaffold --tag backend-architect --allow-tools Bash,Read,Grep,Glob,Agent --ablation with-without --no-publish
claude plugin eval . --scaffold --tag ideate-critic --allow-tools Bash,Read,Grep,Glob,Agent --ablation with-without --no-publish
```

`--scaffold` is required: the fixtures live in each case's `scaffold_script`, which must be a
relative path to an external `.sh` file in the case directory — never inline YAML block content
(see the defect note above).
`tests/evals/test-eval-cases.sh` checks the cases statically (`prompt.md` always, `case.yaml` only
when the case needs scaffolded fixtures, at least one outcome grader, scaffold scripts run and
produce the fixture files, regex graders compile, and each `contract.md` / `clean.md` regex matches
a verdict sample in the shape the agent actually emits: bare, bold, or after a `Verdict:` label —
skipped for agent-dispatch suites with no fixed verdict token, whose content was verified via real
ablation pilots instead) so the suite stays loadable while the runner is gated. Results land in
`evals/results/`, gitignored.
