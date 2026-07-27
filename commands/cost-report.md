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
**cumulative snapshot for that (`session_id`, `model`) pair** — not for the session as a
whole. If a session switches models mid-run (`claude-opus-4-8` for a while, then
`glm-5.2`), each model gets its own independent running counter within the same
session, and a later row can report a *lower* number than an earlier row simply
because it belongs to a different model's counter. **The report takes the latest row
per (`session_id`, `model`) pair and sums across all of them** — taking only the
single latest row per `session_id` (ignoring `model`) silently drops every model's
cost except whichever one happened to be active at the session's last stop, which
undercounted total tracked spend by 55% (confirmed against production data,
2026-07-28: $34,698 reported vs. $53,883 actual — 32 of 362 sessions had switched
models at least once).

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
2. Reduce rows to the latest snapshot per (session, model) pair and aggregate.
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
const bySessionModel=new Map();
for(const r of rows){const k=(r.session_id||r.transcript_path||r.timestamp)+" "+(r.model||"");const p=bySessionModel.get(k);if(!p||String(r.timestamp)>String(p.timestamp))bySessionModel.set(k,r);}
const latest=[...bySessionModel.values()];
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
