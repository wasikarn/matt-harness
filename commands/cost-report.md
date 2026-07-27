---
description: Generate a local Claude Code cost report from the ECC cost-tracker metrics log.
name: cost-report
argument-hint: [csv]
---

# Cost Report

Summarize local Claude Code spend by day, model, and session from the metrics
log that ECC's `stop:cost-tracker` hook writes.

## Where the data lives

The tracker appends one JSON object per session-stop to
`~/.local/share/kbg/metrics/costs.jsonl`. Each row's `estimated_cost_usd` is a
**cumulative snapshot for the whole session** — it sums token usage across every
assistant turn in the transcript from the start, with no per-model split, then prices
that whole-session total at whichever model produced the *most recent* turn. So
`input_tokens`/`output_tokens`/`estimated_cost_usd` are always non-decreasing across a
session's rows, confirmed against production data, 2026-07-28 (all 32 of 362 sessions
that switched models at least once showed monotonic `input_tokens`). **The report
takes the single latest row per `session_id` (ignoring `model`) and sums across
sessions** — this is the whole and correct total (verified by an independent
telescoping-delta recomputation that landed on the identical figure, $34,698.3252,
2026-07-28).

An earlier version of this doc claimed the opposite — that each model kept an
independent per-`session_id`+`model` counter, and that summing the latest row per
(`session_id`, `model`) pair recovered a "55% undercount." That claim was wrong: it
double- and triple-counts the same underlying cumulative tokens every time a session
switches models, inflating the true $34,698 total to a fabricated $53,883. Confirmed
false by reading `hooks/stop/cost-tracker.sh` directly — the row-writing `jq` sums
every assistant message unconditionally, with no `model` filter before the sum.

**Known limitation — the "By model" breakdown is approximate for mixed-model
sessions.** Because a row's cost prices the *entire* session's cumulative tokens at
the currently-active model's rate, a session that switches models has its whole cost
attributed to whichever model was active at the session's last stop — the other
model(s) used earlier in that session show $0 in the breakdown even though they did
real work. This affects ~9% of sessions (32/362, 2026-07-28) and only distorts the
per-model split; the overall total stays correct regardless. A tried fix
(delta-per-row, attributed to that row's model) does exist but overstates the total by
~31% when negative deltas — a real signal from the repricing, not noise — are clamped
to zero to avoid negative per-model figures; discarded as a worse trade. Recovering an
accurate per-model split would require changing `cost-tracker.sh` to accumulate cost
per model incrementally going forward — a hook change, not something reconstructable
from historical rows.

Row schema:
`{ timestamp, session_id, transcript_path, model, input_tokens, output_tokens, cache_write_tokens, cache_read_tokens, rate_verified, estimated_cost_usd }`

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
2. Reduce rows to the latest snapshot per session (by `session_id`, ignoring `model`)
   and aggregate.
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
for(const r of rows){const k=r.session_id||r.transcript_path||r.timestamp;const p=bySession.get(k);if(!p||String(r.timestamp)>String(p.timestamp))bySession.set(k,r);}
const latest=[...bySession.values()];
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
console.log("timestamp,session_id,model,input_tokens,output_tokens,cache_write_tokens,cache_read_tokens,estimated_cost_usd");
for(const r of rows)console.log([r.timestamp,r.session_id,r.model,r.input_tokens,r.output_tokens,r.cache_write_tokens,r.cache_read_tokens,r.estimated_cost_usd].join(","));
'
```

## Report format

1. Summary: today, yesterday, total, session count.
2. By model: models ranked by total cost.
3. Last seven days: date and cost.

Rely on the precomputed `estimated_cost_usd` values written by the tracker; do
not re-estimate pricing from raw tokens here.
