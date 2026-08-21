// Tiered multi-model pipeline: fable plans → sonnet executes → opus reviews
// (fix-retry cap 3, counted here in code per skills/orchestrate/reference.md
// § Concept) → opus bug-hunts fresh-eyes → fable final review, triage-gated on
// contest signals (TAO arXiv:2506.12482: unconditional extra tiers degrade
// agreement — pass args.finalReview = 'always' to force the unconditional form).
// Verdicts are schema-forced; every branch decision is computed in this script,
// never taken from model prose (CLAUDE.md § Architecture, maker≠checker).
// Nothing here commits, pushes, or ships — the result returns to a human.
// KNOWN LIMIT (verified 2026-08-21, 5-form probe): this environment runs every
// subagent — Workflow opts.model, opts.agentType's own model pin, and the plain
// Agent tool's model param alike — on the session default model. The pins below
// are declared intent, honored only where the platform supports per-agent override.
// The load-bearing separation (fresh context per stage, deterministic branching,
// capped retries, triage-gated final tier) holds regardless of which model runs.
// Usage: Workflow({scriptPath: 'scripts/workflows/tiered-pipeline.js',
//   args: {task: '...', cwd: '/abs/path'?, finalReview: 'always'?}})
export const meta = {
  name: 'tiered-pipeline',
  description: 'Fable plans, Sonnet executes, Opus reviews with capped fixes, Opus bug-hunts, gated Fable final review',
  whenToUse: 'Run one bounded implementation task through the tiered maker/checker pipeline',
  phases: [
    { title: 'Plan', detail: 'survey + plan with mechanical acceptance criteria', model: 'fable' },
    { title: 'Execute', detail: 'implement the plan, verify criteria', model: 'sonnet' },
    { title: 'Review', detail: 'independent re-verification; fix loop capped at 3', model: 'opus' },
    { title: 'Bug-hunt', detail: 'fresh-eyes adversarial pass, shares the same fix cap', model: 'opus' },
    { title: 'Final', detail: 'runs only when contested (fixes used or low confidence)', model: 'fable' },
  ],
}

const FIX_CAP = 3
const CONF_FLOOR = 0.75

const task = args && args.task
if (!task) throw new Error('args.task is required: {task: "...", cwd: "/abs/path"?, finalReview: "always"?}')
const cwdLine = args && args.cwd ? `Working directory (use absolute paths under it): ${args.cwd}` : ''

const FINDING = {
  type: 'object',
  required: ['severity', 'description'],
  properties: {
    severity: { enum: ['critical', 'major', 'minor'] },
    description: { type: 'string' },
    location: { type: 'string' },
  },
}
const VERDICT = {
  type: 'object',
  required: ['pass', 'findings', 'confidence', 'scope_ok'],
  properties: {
    pass: { type: 'boolean' },
    findings: { type: 'array', items: FINDING },
    confidence: { type: 'number', minimum: 0, maximum: 1 },
    scope_ok: { type: 'boolean' },
  },
}
const PLAN = {
  type: 'object',
  required: ['objective', 'steps', 'acceptance_criteria'],
  properties: {
    objective: { type: 'string' },
    steps: { type: 'array', items: { type: 'string' } },
    acceptance_criteria: { type: 'array', items: { type: 'string' } },
    risks: { type: 'array', items: { type: 'string' } },
  },
}
const EXEC = {
  type: 'object',
  required: ['summary', 'files_changed', 'criteria_results'],
  properties: {
    summary: { type: 'string' },
    files_changed: { type: 'array', items: { type: 'string' } },
    criteria_results: {
      type: 'array',
      items: {
        type: 'object',
        required: ['criterion', 'met', 'evidence'],
        properties: { criterion: { type: 'string' }, met: { type: 'boolean' }, evidence: { type: 'string' } },
      },
    },
  },
}
const FINAL = {
  type: 'object',
  required: ['approve', 'reasoning', 'residual_risks'],
  properties: {
    approve: { type: 'boolean' },
    reasoning: { type: 'string' },
    residual_risks: { type: 'array', items: { type: 'string' } },
  },
}

// Fail-closed: a missing/malformed verdict is a rejection, never a pass.
const failClosed = (v, who) =>
  v && typeof v.pass === 'boolean' && Array.isArray(v.findings) && typeof v.confidence === 'number'
    ? v
    : { pass: false, findings: [{ severity: 'critical', description: `${who}: verdict missing or malformed — fail-closed` }], confidence: 0, scope_ok: false }

phase('Plan')
const plan = await agent(
  `You are the planning tier of a tiered pipeline. Task:

<task>${task}</task>
${cwdLine}

Survey whatever context you need — READ-ONLY, do not create or edit any file. Produce an implementation plan: concrete ordered steps, and acceptance criteria a reviewer can verify mechanically (a file exists, a command exits 0, input X yields Y) — never vibes. List real risks if any.`,
  { model: 'fable', label: 'plan:fable', phase: 'Plan', schema: PLAN },
)
if (!plan) throw new Error('planner returned nothing')
log(`Plan: ${plan.steps.length} steps, ${plan.acceptance_criteria.length} acceptance criteria`)

phase('Execute')
const exec = await agent(
  `You are the execution tier. Implement this plan exactly; stay strictly inside its scope.

<task>${task}</task>
<plan>${JSON.stringify(plan)}</plan>
${cwdLine}

Do the work now — create/edit files, run commands. Then verify EVERY acceptance criterion yourself and report each with observed evidence (actual command output, not "should work").`,
  { model: 'sonnet', label: 'execute:sonnet', phase: 'Execute', schema: EXEC },
)
if (!exec) throw new Error('executor returned nothing')

const reviewPrompt = (round) =>
  `You are the review tier, round ${round}. Independently verify the work below — do NOT trust the executor's report; re-read the files and re-run the checks yourself.

<task>${task}</task>
<plan>${JSON.stringify(plan)}</plan>
Files claimed changed: ${JSON.stringify(exec.files_changed)}
${cwdLine}

Verify: every acceptance criterion actually holds (re-run it), scope respected (scope_ok=false if unrelated files were touched), correctness and edge cases. pass=true only if all criteria verified AND no critical/major finding. confidence: your 0-1 confidence in this verdict.`

const fixPrompt = (n, findings) =>
  `You are the fixer, attempt ${n} of ${FIX_CAP}. A reviewer rejected the work. Fix EXACTLY these findings — nothing else.

<task>${task}</task>
Findings to fix: ${JSON.stringify(findings)}
${cwdLine}

Fix, re-run the relevant checks, report what changed with evidence.`

phase('Review')
let fixAttempts = 0
let verdict = failClosed(await agent(reviewPrompt(1), { model: 'opus', label: 'review:opus:r1', phase: 'Review', schema: VERDICT }), 'review r1')
const confidences = [verdict.confidence]
const reviewRounds = [verdict]
while (!verdict.pass && fixAttempts < FIX_CAP) {
  fixAttempts++
  log(`Review round ${reviewRounds.length} failed (${verdict.findings.length} findings) — fix attempt ${fixAttempts}/${FIX_CAP}`)
  await agent(fixPrompt(fixAttempts, verdict.findings), { model: 'sonnet', label: `fix:sonnet:${fixAttempts}`, phase: 'Review', schema: EXEC })
  verdict = failClosed(
    await agent(reviewPrompt(reviewRounds.length + 1), { model: 'opus', label: `review:opus:r${reviewRounds.length + 1}`, phase: 'Review', schema: VERDICT }),
    `review r${reviewRounds.length + 1}`,
  )
  reviewRounds.push(verdict)
  confidences.push(verdict.confidence)
}
if (!verdict.pass) {
  log(`Fix-retry cap (${FIX_CAP}) exhausted — escalating to human, not re-dispatching`)
  return { status: 'escalated', stage: 'review', reason: `fix-retry cap ${FIX_CAP} exhausted`, plan, execution: exec, reviewRounds, fixAttempts, openFindings: verdict.findings }
}

phase('Bug-hunt')
const huntPrompt = (round) =>
  `You are an adversarial bug-hunter with fresh eyes, round ${round}. A prior review already passed this work — your job is to break it anyway.

<task>${task}</task>
Acceptance criteria: ${JSON.stringify(plan.acceptance_criteria)}
Files: ${JSON.stringify(exec.files_changed)}
${cwdLine}

Actively attack it: hostile inputs, edge cases the criteria never named, actually run the code and tests. pass=false only for a real, demonstrated defect — include the repro in the finding description. Style nits are severity minor, and minor-only findings still allow pass=true.`

let hunt = failClosed(await agent(huntPrompt(1), { model: 'opus', label: 'bughunt:opus:r1', phase: 'Bug-hunt', schema: VERDICT }), 'bughunt r1')
confidences.push(hunt.confidence)
let huntRounds = 1
while (!hunt.pass && fixAttempts < FIX_CAP) {
  fixAttempts++
  log(`Bug-hunt found real defects — fix attempt ${fixAttempts}/${FIX_CAP} (shared cap)`)
  await agent(fixPrompt(fixAttempts, hunt.findings), { model: 'sonnet', label: `fix:sonnet:${fixAttempts}`, phase: 'Bug-hunt', schema: EXEC })
  huntRounds++
  hunt = failClosed(await agent(huntPrompt(huntRounds), { model: 'opus', label: `bughunt:opus:r${huntRounds}`, phase: 'Bug-hunt', schema: VERDICT }), `bughunt r${huntRounds}`)
  confidences.push(hunt.confidence)
}
if (!hunt.pass) {
  log(`Fix-retry cap (${FIX_CAP}) exhausted in bug-hunt — escalating to human`)
  return { status: 'escalated', stage: 'bug-hunt', reason: `fix-retry cap ${FIX_CAP} exhausted`, plan, execution: exec, reviewRounds, huntVerdict: hunt, fixAttempts, openFindings: hunt.findings }
}

phase('Final')
const minConfidence = Math.min(...confidences)
const contested = fixAttempts > 0 || minConfidence < CONF_FLOOR
const forced = args && args.finalReview === 'always'
let finalReview
if (contested || forced) {
  const why = forced && !contested ? 'forced by args.finalReview=always' : `contested: ${fixAttempts} fix attempt(s), min confidence ${minConfidence}`
  log(`Final fable review runs — ${why}`)
  const fr = await agent(
    `You are the final review tier, called in because this run was ${why}. You advise; a human decides — nothing ships on your say-so.

<task>${task}</task>
<plan>${JSON.stringify(plan)}</plan>
Review rounds: ${JSON.stringify(reviewRounds)}
Bug-hunt verdict: ${JSON.stringify(hunt)}
Fix attempts used: ${fixAttempts}/${FIX_CAP}
${cwdLine}

Independently spot-check the highest-risk parts on disk (read files, re-run the riskiest check), then recommend approve or not, with residual risks a human should weigh.`,
    { model: 'fable', label: 'final:fable', phase: 'Final', schema: FINAL },
  )
  finalReview = fr || { approve: false, reasoning: 'final reviewer returned nothing — fail-closed', residual_risks: [] }
} else {
  log(`Final fable review SKIPPED — uncontested (0 fix attempts, min confidence ${minConfidence} >= ${CONF_FLOOR}). Triage gate per TAO arXiv:2506.12482; force with args.finalReview='always'.`)
  finalReview = { skipped: true, reason: `uncontested: 0 fix attempts, min confidence ${minConfidence} >= ${CONF_FLOOR}` }
}

const approved = finalReview.skipped === true || finalReview.approve === true
return {
  status: approved ? 'approved' : 'needs-human',
  plan,
  execution: exec,
  reviewRounds,
  huntVerdict: hunt,
  fixAttempts,
  minConfidence,
  finalReview,
}
