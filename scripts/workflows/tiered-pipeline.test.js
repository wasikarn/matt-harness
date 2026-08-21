// Regression tests for tiered-pipeline.js's approval/branch logic — runs the
// real script body under stubbed Workflow-runtime globals (agent/phase/log/args).
// Born from a compliance-audit adversarial finding (2026-08-21): a schema-valid
// final-review reply carrying an extra `skipped: true` field flipped an explicit
// approve:false into status 'approved'. Run: node scripts/workflows/tiered-pipeline.test.js
'use strict'
const fs = require('fs')
const path = require('path')
const assert = require('assert')

const src = fs.readFileSync(path.join(__dirname, 'tiered-pipeline.js'), 'utf8')
const body = src.replace(/^export const meta = \{[\s\S]*?\n\}\n/m, '')
assert.ok(!body.includes('export const meta'), 'meta block strip failed')
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
// 'use strict' prepended: the shipped file is an ES module (implicitly strict);
// a sloppy-mode AsyncFunction body would let a bare-assignment typo pass here
// while throwing ReferenceError in the real Workflow run (2026-08-22 review).
const pipeline = new AsyncFunction('agent', 'phase', 'log', 'args', 'parallel', 'workflow', 'budget', "'use strict';\n" + body)

// Stub: routes on the label each agent() call declares; counts calls per label prefix.
function makeAgent(replies, calls) {
  return async (_prompt, opts) => {
    const label = (opts && opts.label) || ''
    calls.push(label)
    for (const prefix of Object.keys(replies)) if (label.startsWith(prefix)) return replies[prefix](label)
    throw new Error(`no stub for label: ${label}`)
  }
}
const noop = () => {}
const PLAN = () => ({ objective: 'x', steps: ['s'], acceptance_criteria: ['c'], risks: [] })
const EXEC = () => ({ summary: 's', files_changed: [], criteria_results: [] })
const OK = (conf) => () => ({ pass: true, findings: [], confidence: conf, scope_ok: true })

async function run(replies) {
  const calls = []
  const result = await pipeline(makeAgent(replies, calls), noop, noop, { task: 't' })
  return { result, calls }
}

;(async () => {
  // T1 — field-injection bypass: low review confidence forces the final tier;
  // final says approve:false but smuggles skipped:true → must be needs-human, never approved.
  {
    const { result } = await run({
      'plan:': PLAN, 'execute:': EXEC,
      'review:': OK(0.5), 'bughunt:': OK(0.9),
      'final:': () => ({ approve: false, reasoning: 'real defect', residual_risks: [], skipped: true }),
    })
    assert.strictEqual(result.status, 'needs-human', `T1 injection bypass: got ${result.status}`)
    console.log('PASS: T1 finalReview skipped-injection cannot flip approve:false')
  }

  // T2 — scope_ok gates: pass:true + scope_ok:false must count as a failure,
  // burn the 3-attempt cap, and escalate (never sail through as a clean pass).
  {
    const { result, calls } = await run({
      'plan:': PLAN, 'execute:': EXEC, 'fix:': EXEC,
      'review:': () => ({ pass: true, findings: [], confidence: 0.9, scope_ok: false }),
    })
    assert.strictEqual(result.status, 'escalated', `T2 scope_ok inert: got ${result.status}`)
    assert.strictEqual(result.stage, 'review', 'T2 wrong stage')
    assert.strictEqual(calls.filter((l) => l.startsWith('fix:')).length, 3, 'T2 fix cap not 3')
    console.log('PASS: T2 scope_ok=false fails the review and the cap holds at 3')
  }

  // T3 — clean run: triage gate skips the final tier entirely, no final agent call.
  {
    const { result, calls } = await run({
      'plan:': PLAN, 'execute:': EXEC, 'review:': OK(0.95), 'bughunt:': OK(0.95),
      'final:': () => { throw new Error('final must not be called on a clean run') },
    })
    assert.strictEqual(result.status, 'approved', `T3: got ${result.status}`)
    assert.strictEqual(result.finalReview.skipped, true, 'T3 finalReview not marked skipped')
    assert.strictEqual(calls.filter((l) => l.startsWith('final:')).length, 0, 'T3 final tier ran')
    console.log('PASS: T3 uncontested run skips the final tier')
  }

  // T4 — NaN confidence is not a number that counts: failClosed must reject it.
  {
    const { result } = await run({
      'plan:': PLAN, 'execute:': EXEC, 'fix:': EXEC,
      'review:': () => ({ pass: true, findings: [], confidence: NaN, scope_ok: true }),
    })
    assert.strictEqual(result.status, 'escalated', `T4 NaN confidence: got ${result.status}`)
    console.log('PASS: T4 NaN confidence fails closed')
  }

  // T5/T6 — a null plan or executor result escalates structurally, never throws.
  {
    const { result } = await run({ 'plan:': () => null })
    assert.strictEqual(result.status, 'escalated', `T5: got ${result.status}`)
    assert.strictEqual(result.stage, 'plan', 'T5 wrong stage')
    console.log('PASS: T5 null plan escalates with stage=plan')
  }
  {
    const { result } = await run({ 'plan:': PLAN, 'execute:': () => null })
    assert.strictEqual(result.status, 'escalated', `T6: got ${result.status}`)
    assert.strictEqual(result.stage, 'execute', 'T6 wrong stage')
    console.log('PASS: T6 null exec escalates with stage=execute')
  }

  // T7 — pass:true contradicted by a critical finding must be demoted, not trusted.
  // Bug-hunt leg deliberately: un-demoted it would skip the final tier and approve
  // with no tier ever having looked at the contradiction (2026-08-22 HIGH finding).
  {
    const { result, calls } = await run({
      'plan:': PLAN, 'execute:': EXEC, 'fix:': EXEC,
      'review:': OK(0.9),
      'bughunt:': () => ({ pass: true, findings: [{ severity: 'critical', description: 'SQLi still present' }], confidence: 0.9, scope_ok: true }),
    })
    assert.strictEqual(result.status, 'escalated', `T7 pass+critical sailed through: got ${result.status}`)
    assert.strictEqual(result.stage, 'bug-hunt', 'T7 wrong stage')
    assert.strictEqual(calls.filter((l) => l.startsWith('fix:')).length, 3, 'T7 demotion did not drive the fix loop')
    console.log('PASS: T7 pass:true + critical finding is demoted, never approved')
  }

  // T8 — confidence outside the schema's [0,1] (e.g. a 0-100 mis-scale) is malformed:
  // 50 must not defeat the CONF_FLOOR triage gate by reading as "very confident".
  {
    const { result } = await run({
      'plan:': PLAN, 'execute:': EXEC, 'fix:': EXEC,
      'review:': () => ({ pass: true, findings: [], confidence: 50, scope_ok: true }),
    })
    assert.strictEqual(result.status, 'escalated', `T8 out-of-range confidence trusted: got ${result.status}`)
    assert.strictEqual(result.stage, 'review', 'T8 wrong stage')
    console.log('PASS: T8 confidence outside [0,1] fails closed')
  }

  // T9/T10 — truthy-but-malformed plan/exec (missing required arrays) escalates
  // structurally, same contract as the null case in T5/T6 — never a crash, never
  // a silent "undefined" spliced into downstream prompts.
  {
    const { result } = await run({ 'plan:': () => ({ objective: 'x' }) })
    assert.strictEqual(result.status, 'escalated', `T9: got ${result.status}`)
    assert.strictEqual(result.stage, 'plan', 'T9 wrong stage')
    console.log('PASS: T9 plan missing required arrays escalates with stage=plan')
  }
  {
    const { result } = await run({
      'plan:': PLAN, 'execute:': () => ({ summary: 's', criteria_results: [] }),
      'review:': OK(0.95), 'bughunt:': OK(0.95),
    })
    assert.strictEqual(result.status, 'escalated', `T10: got ${result.status}`)
    assert.strictEqual(result.stage, 'execute', 'T10 wrong stage')
    console.log('PASS: T10 exec missing files_changed escalates with stage=execute')
  }

  // T11 — the fix cap is SHARED across review and bug-hunt: review burns 1 attempt,
  // bug-hunt gets only the remaining 2 before escalating. A future split into
  // per-stage caps (4+ total fixes) must fail here.
  {
    const FAILV = () => ({ pass: false, findings: [{ severity: 'major', description: 'd' }], confidence: 0.9, scope_ok: true })
    const { result, calls } = await run({
      'plan:': PLAN, 'execute:': EXEC, 'fix:': EXEC,
      'review:': (label) => (label.endsWith(':r1') ? FAILV() : OK(0.9)()),
      'bughunt:': FAILV,
    })
    assert.strictEqual(result.status, 'escalated', `T11: got ${result.status}`)
    assert.strictEqual(result.stage, 'bug-hunt', 'T11 wrong stage')
    assert.strictEqual(calls.filter((l) => l.startsWith('fix:')).length, 3, 'T11 shared cap exceeded — per-stage caps snuck in')
    console.log('PASS: T11 fix cap is shared across review and bug-hunt, total never exceeds 3')
  }

  console.log('ALL GREEN')
})().catch((e) => { console.error('FAIL:', e.message); process.exit(1) })
