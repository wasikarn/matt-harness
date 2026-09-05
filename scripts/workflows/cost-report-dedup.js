#!/usr/bin/env node
// cost-report-dedup.js — the mh:cost-report skill's report + CSV logic.
// Extracted verbatim from skills/meta/cost-report/SKILL.md's two embedded fences
// (2026-08-23, 200-LOC cap refactor) so the command body stays under cap and
// this logic is directly testable: tests/skills/test-cost-report.sh runs
// this file, not a fence extraction. Old rows may carry extra fields from
// retired schemas; unknown keys are ignored.
// Usage: node cost-report-dedup.js        -> summary report
//        node cost-report-dedup.js csv    -> CSV of the last 100 raw rows
const fs=require("fs"),os=require("os"),path=require("path");
const f=path.join(os.homedir(),".local","share","kbg","metrics","costs.jsonl");

if(process.argv[2]==="csv"){
  if(!fs.existsSync(f)){console.error("no data");process.exit(0);}
  const rows=fs.readFileSync(f,"utf8").split(/\r?\n/).filter(Boolean).map(l=>{try{return JSON.parse(l)}catch{return null}}).filter(Boolean).slice(-100);
  console.log("timestamp,session_id,model,model_scoped,stream,agent_type,turns,input_tokens,output_tokens,cache_write_tokens,cache_read_tokens,cache_read_per_turn,estimated_cost_usd");
  for(const r of rows)console.log([r.timestamp,r.session_id,r.model,r.model_scoped===true,r.stream||"",r.agent_type||"",r.turns||"",r.input_tokens,r.output_tokens,r.cache_write_tokens,r.cache_read_tokens,r.cache_read_per_turn||"",r.estimated_cost_usd].join(","));
  process.exit(0);
}

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
// Two eras (2026-09-04): rows without dedup_usage summed one line per content block, ~2.4x high on
// turns/tokens; dedup_usage rows without usage_pick:"last" (v0.68.639) kept the first line per
// message.id, whose output_tokens is a streaming placeholder — ~39% low on output_tokens.
const inflated=latest.filter(r=>r.dedup_usage!==true).length;
const outLow=latest.filter(r=>r.dedup_usage===true&&r.usage_pick!=="last").length;
if(inflated)console.log("note: "+inflated+" of "+latest.length+" rows predate dedup_usage (2026-09-04) — their turns/tokens run ~2.4x high (per-line, not per-response)");
if(outLow)console.log("note: "+outLow+" of "+latest.length+" rows predate usage_pick:\"last\" (v0.68.641) — their output_tokens (and cost) run ~39% low (first line per response, not last)");
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
const typed=latest.filter(r=>r.stream==="subagent");
if(typed.length){
  console.log("\n=== By agent type (subagent spend only; rows tagged 2026-08-07+; tok = input+output, rank by it when rate unverified) ===");
  const m=new Map();for(const r of typed){const k=r.agent_type||"(unknown)";const p=m.get(k)||{c:0,t:0};p.c+=cost(r);p.t+=(Number(r.input_tokens)||0)+(Number(r.output_tokens)||0);m.set(k,p);}
  for(const [k,v] of [...m.entries()].sort((a,b)=>b[1].c-a[1].c||b[1].t-a[1].t))console.log(f4(v.c).padStart(12)+"  "+String(v.t).padStart(10)+" tok  "+k);
}
console.log("\n=== Last 7 days ===");
const days=new Map();for(const r of latest){const k=day(r);days.set(k,(days.get(k)||0)+cost(r));}
[...days.entries()].sort((a,b)=>b[0]<a[0]?-1:1).slice(0,7).forEach(([k,v])=>console.log(k+"  "+f4(v)));
