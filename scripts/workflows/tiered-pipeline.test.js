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
const pipeline = new AsyncFunction('agent', 'phase', 'log', 'args', 'parallel', 'workflow', 'budget', body)

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

  console.log('ALL GREEN')
})().catch((e) => { console.error('FAIL:', e.message); process.exit(1) })
