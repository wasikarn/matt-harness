---
description: Generate a local Claude Code cost report from the ECC cost-tracker metrics log.
name: cost-report
argument-hint: [csv]
---

# Cost Report

Summarize local Claude Code spend by day, model, and session from the metrics
log that ECC's `stop:cost-tracker` hook writes.

## Where the data lives

The tracker appends one or more JSON objects per session-stop to
`~/.local/share/kbg/metrics/costs.jsonl`, one per **model actually used in that
session so far, split further by `agent_type` for subagent spend**. Every stop
re-derives cumulative totals from the full transcript (stateless — no separate counter
file), groups assistant turns by `.message.model` (and, within the subagent stream, by
`agent_type`), and writes each model's own true cumulative `input_tokens`/
`output_tokens`/`estimated_cost_usd`, priced at that model's own rate. These rows carry
`model_scoped: true`. **The report takes the latest row per (`session_id`, `stream`,
`model`, `agent_type`) key among `model_scoped` rows and sums across a session's keys**
— a streamless row (written before 2026-08-07, when `stream` shipped) is treated as
`stream: "orchestrator"` for this key, not as a fourth bucket; see the double-counting
bug this fixed, below. The hook's per-model
token computation was verified against a real 3-model production transcript
(`claude-opus-4-8`, `claude-sonnet-5`, `glm-5.2`) by running the actual hook end-to-end
and confirming each model's cost matched a hand computation from the raw token counts,
2026-07-28 — this predates the claude-only filter added 2026-08-07 (below); the third
model in that transcript is cited only as evidence the grouping math handles more than
one model correctly, not as a claim the hook still tracks it today. The report's own aggregation of `model_scoped` rows is only regression-gated
against a single-row synthetic case so far (zero `model_scoped` rows exist in production
data as of this writing — the installed plugin hook won't write them until this version
ships and a session stops under it) — treat the multi-row aggregation path as untested
by real data until the first genuinely multi-model session produces it.

**Rows written before this fix (no `model_scoped` field) used a different, coarser
design**: one row per stop, summing token usage across the *entire* transcript with no
per-model split, then pricing that whole-session total at whichever model produced the
most recent turn. A session that switched models had its `input_tokens`/
`estimated_cost_usd` monotonically increasing regardless of which model was active —
confirmed against production data, 2026-07-28 (all 32 of 362 sessions that switched
models at least once showed monotonic `input_tokens` under the old design). **For a
session with no `model_scoped` rows at all** (it stopped for the last time before this
fix shipped, so it will never get an updated row), the report falls back to the old
behavior: dedup by `session_id` alone, take the single latest row — this is the
correct aggregation of what the old design recorded (verified by an independent
telescoping-delta recomputation that landed on the identical figure, $34,698.3252,
2026-07-28), and it's the best available total for a session that can't be re-measured.
A session with at least one `model_scoped` row uses **only** those rows for its total,
never mixed with its own older rows — a `model_scoped` row recomputes from the whole
transcript, so it already supersedes anything the old design recorded earlier in that
same session.

**Prior mistake, corrected the same day:** an earlier version of this doc, and an
earlier version of the hook's row-writing logic, both assumed (wrongly, before either
was actually read) that old-format rows already carried an independent per-model
counter, and "fixed" the report by deduping old rows on (`session_id`, `model`) and
summing. That inflated the true $34,698 total to a fabricated $53,883 — old rows are
whole-session snapshots, and summing several of them for one session double- and
triple-counts the same cumulative tokens. Reverted before that shipped; this hook
change is what makes the (`session_id`, `model`) dedup actually correct, for
`model_scoped` rows only.

Neither design is a correct *dollar* total on its own, though: whichever model doesn't
match `haiku`/`opus`/`sonnet` in the tracker's rate table falls back to the Sonnet rate
as a guess (`rate_verified: false`) — on 2026-07-28's data (still mostly old-format
rows at that point) that was over half the total, $17,510 of $34,698, priced at a rate
that isn't the actual model's. The report's `(rate unverified)` tag on each affected
model is the only signal of this; take any total as "correctly summed," not
"correctly priced," until every model in the rate table is a real, verified rate.

Row schema:
`{ timestamp, session_id, transcript_path, model, model_scoped, stream, agent_type, turns, input_tokens, output_tokens, cache_write_tokens, cache_read_tokens, cache_read_per_turn, rate_verified, estimated_cost_usd }`

`model_scoped` is `true` on rows written by the per-model design; absent (falsy) on
rows written by the old whole-session design — see above for how the report treats
each.

`stream` is `"orchestrator"` (the main thread, `.transcript_path`) or `"subagent"`
(every file under the sibling `<session-id>/subagents/` directory), added 2026-08-07.
Absent on all rows written before that — those are orchestrator-only totals, because
the hook never read the subagent directory at all, so subagent spend was missing from
every historical row rather than folded into it. **Do not compare a pre-2026-08-07
session's total against a later one and read the difference as a spending change.**

Because both streams can carry the same `model` inside one session, the
(`session_id`, `model`) dedup key is now (`session_id`, `stream`, `model`) — without
`stream` in the key the two rows collide and one is silently dropped, which is the
same undercount the split was added to fix.

`agent_type` is the Agent tool's `subagent_type` value (`"general-purpose"`,
`"Explore"`, `"kbg:code-reviewer"`, …), read from the `agentType` field in each
subagent's `agent-<id>.meta.json` sibling — added 2026-08-07. `null` on every
orchestrator row (the main thread has no subagent type); `"unknown"` on a subagent row
whose meta.json was missing or unreadable, so a lookup gap never silently drops spend.
The dedup key widens to (`session_id`, `stream`, `model`, `agent_type`) for the same
reason `stream` was added to it: two agent types spending on the same model inside one
session are two different rows, not duplicates of each other — without `agent_type` in
the key, one collides into the other and its spend is silently dropped.

**Claude-only, at operator request (2026-08-07).** A session can run non-Claude models
— a proxy that swaps `ANTHROPIC_BASE_URL` — and production data confirmed real spend
this way (`minimax-m3`, `glm-5.2`, `kimi-k2.7-code`, `nemotron-3-super`). The hook now
drops any assistant turn whose `.message.model` doesn't match `claude-*` before
grouping — not priced at a guessed rate, not folded into an `"unknown"` row, simply not
written. A transcript with no Claude turns at all writes no row. Historical rows
already in `costs.jsonl` for non-Claude models are untouched by this change — it only
affects what future stops write; the report still sums whatever `model_scoped` rows
already exist, Claude or not.

`turns` is the assistant-turn count behind the row, and `cache_read_per_turn` is
`cache_read_tokens ÷ turns` **for that row's own model** — the hook groups by model
before counting turns, so a session that switched models has one such ratio per model,
not one for the session. The By-stream block below re-derives a session-level figure by
summing tokens and turns across every orchestrator row first, then dividing; that
deliberately mixes models, because the question there is how much context the main
thread carried, not which model it was talking to. On the orchestrator row that ratio is the useful one: it
measures how much context the main thread carries into *every* turn, re-billed each
time, which is the cost the article "The Orchestrator's Tax" names and the reason for
this split — `docs/research/orchestrator-tax-gap-analysis-2026-08-07.md`. A rising
`cache_read_per_turn` across sessions means the main thread is accumulating more than
it needs; that number, not the dollar total, is the one to watch.

`rate_verified` is `false` when `model` didn't match a known pricing tier
(`haiku`/`opus`/`sonnet`) — the cost was estimated at the Sonnet rate as a
guess, not a matched price.

`timestamp` is stored in UTC (`Z` suffix), but "today"/"yesterday"/the last-7-days
buckets are computed from each `Date`'s **local** calendar fields (`getFullYear`/
`getMonth`/`getDate`, not `toISOString`) — matching UTC calendar days instead would
put several hours of a user's actual "today" spend under "yesterday" for anyone
west of UTC (reproduced live against production data, 2026-07-28: at 01:51 local in
UTC+7, UTC's calendar date was still the prior day, and the UTC-bucketed report
showed $972 for "today" — mostly the actual prior day's spend — and $1.53 for
"yesterday"). This depends on the Node process's own resolved local timezone
(`Intl.DateTimeFormat().resolvedOptions().timeZone`, which follows the machine's
system timezone setting when `TZ` is unset) — correct for the normal case of a user
running this command interactively on their own machine, but if it's ever invoked in
a context whose system/`TZ` timezone doesn't match the reader's own (a container, a
remote/headless session), the buckets will follow that environment's zone instead.

## What this command does

1. Check that `~/.local/share/kbg/metrics/costs.jsonl` exists. If it does not, tell the
   user the tracker is not set up yet (it populates after the first session ends
   with the `stop:cost-tracker` hook enabled).
2. For each session: if it has any `model_scoped` row, reduce to the latest row per
   (`session_id`, `stream`, `model`, `agent_type`) key and sum across them; otherwise
   reduce to the single latest row per `session_id` (ignoring `model`). Aggregate
   across sessions.
3. Present a compact report, or export recent rows as CSV when the argument is `csv`.

`node` is used instead of `sqlite3`/`jq` so this works identically on macOS,
Linux, and Windows.

## Report

```bash
node -e '
const fs=require("fs"),os=require("os"),path=require("path");
const f=path.join(os.homedir(),".local","share","kbg","metrics","costs.jsonl");
if(!fs.existsSync(f)){console.log("Cost tracker not set up: "+f+" not found. Enable the stop:cost-tracker hook and finish a session first.");process.exit(0);}
const rows=fs.readFileSync(f,"utf8").split(/\r?\n/).filter(Boolean).map(l=>{try{return JSON.parse(l)}catch{return null}}).filter(Boolean);
const bySession=new Map();
for(const r of rows){const k=r.session_id||r.transcript_path||r.timestamp;if(!bySession.has(k))bySession.set(k,[]);bySession.get(k).push(r);}
const latest=[];
for(const rs of bySession.values()){
  const scoped=rs.filter(r=>r.model_scoped===true);
  if(scoped.length){
    const byModel=new Map();
    for(const r of scoped){const k=(r.stream||"orchestrator")+" "+(r.model||"")+" "+(r.agent_type||"");const p=byModel.get(k);if(!p||String(r.timestamp)>String(p.timestamp))byModel.set(k,r);}
    latest.push(...byModel.values());
  }else{
    let best=null;
    for(const r of rs){if(!best||String(r.timestamp)>String(best.timestamp))best=r;}
    if(best)latest.push(best);
  }
}
const cost=r=>Number(r.estimated_cost_usd)||0;
const fmtLocal=dt=>dt.getFullYear()+"-"+String(dt.getMonth()+1).padStart(2,"0")+"-"+String(dt.getDate()).padStart(2,"0");
const day=r=>fmtLocal(new Date(r.timestamp));
const today=fmtLocal(new Date());
const d=fmtLocal(new Date(Date.now()-864e5));
const sum=a=>a.reduce((s,r)=>s+cost(r),0);
const f4=n=>"$"+n.toFixed(4);
console.log("=== Cost summary ===");
console.log("today:     "+f4(sum(latest.filter(r=>day(r)===today))));
console.log("yesterday: "+f4(sum(latest.filter(r=>day(r)===d))));
const sessionIds=new Set(latest.map(r=>r.session_id||r.transcript_path||r.timestamp));
console.log("total:     "+f4(sum(latest))+"  ("+sessionIds.size+" sessions)");
const by=(key)=>{const m=new Map();for(const r of latest){const k=key(r)||"(unknown)";m.set(k,(m.get(k)||0)+cost(r));}return [...m.entries()].sort((a,b)=>b[1]-a[1]);};
const unverified=new Set(latest.filter(r=>r.rate_verified===false).map(r=>r.model||"(unknown)"));
console.log("\n=== By model ===");for(const [k,v] of by(r=>r.model))console.log(f4(v).padStart(12)+"  "+k+(unverified.has(k)?"  (rate unverified)":""));
const tagged=latest.filter(r=>r.stream);
if(tagged.length){
  console.log("\n=== By stream (rows tagged 2026-08-07+; older rows are orchestrator-only and excluded) ===");
  for(const [k,v] of by(r=>r.stream)){if(k==="(unknown)")continue;console.log(f4(v).padStart(12)+"  "+k);}
  const orch=tagged.filter(r=>r.stream==="orchestrator");
  const turns=orch.reduce((s,r)=>s+(Number(r.turns)||0),0);
  const cr=orch.reduce((s,r)=>s+(Number(r.cache_read_tokens)||0),0);
  if(turns)console.log("\norchestrator context carried per turn: "+Math.round(cr/turns).toLocaleString()+" tokens  (re-read every turn — the rent meter)");
}
const typed=latest.filter(r=>r.stream==="subagent"&&r.agent_type);
if(typed.length){
  console.log("\n=== By agent type (subagent spend only; rows tagged 2026-08-07+) ===");
  for(const [k,v] of by(r=>r.agent_type)){if(k==="(unknown)")continue;console.log(f4(v).padStart(12)+"  "+k);}
}
console.log("\n=== Last 7 days ===");
const days=new Map();for(const r of latest){const k=day(r);days.set(k,(days.get(k)||0)+cost(r));}
[...days.entries()].sort((a,b)=>b[0]<a[0]?-1:1).slice(0,7).forEach(([k,v])=>console.log(k+"  "+f4(v)));
'
```

## CSV export (`/cost-report csv`)

```bash
node -e '
const fs=require("fs"),os=require("os"),path=require("path");
const f=path.join(os.homedir(),".local","share","kbg","metrics","costs.jsonl");
if(!fs.existsSync(f)){console.error("no data");process.exit(0);}
const rows=fs.readFileSync(f,"utf8").split(/\r?\n/).filter(Boolean).map(l=>{try{return JSON.parse(l)}catch{return null}}).filter(Boolean).slice(-100);
console.log("timestamp,session_id,model,model_scoped,stream,agent_type,turns,input_tokens,output_tokens,cache_write_tokens,cache_read_tokens,cache_read_per_turn,estimated_cost_usd");
for(const r of rows)console.log([r.timestamp,r.session_id,r.model,r.model_scoped===true,r.stream||"",r.agent_type||"",r.turns||"",r.input_tokens,r.output_tokens,r.cache_write_tokens,r.cache_read_tokens,r.cache_read_per_turn||"",r.estimated_cost_usd].join(","));
'
```

## Report format

1. Summary: today, yesterday, total, session count.
2. By model: models ranked by total cost.
3. By stream: orchestrator vs subagent, plus the orchestrator's context-carried-per-turn.
   Omitted entirely when no row carries `stream` (all data predates 2026-08-07).
4. By agent type: subagent spend only, ranked by `agent_type`. Omitted entirely when
   no subagent row carries `agent_type` (all data predates 2026-08-07).
5. Last seven days: date and cost.

Rely on the precomputed `estimated_cost_usd` values written by the tracker; do
not re-estimate pricing from raw tokens here.
