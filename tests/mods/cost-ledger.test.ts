import { test, expect, type TestBody } from 'claude-code/testing'
import { ledgerDelta } from '../../hooks/mod/cost-ledger'

// Unit tests for hooks/mod/cost-ledger.ts, run by `claude plugin test .` from the repo root
// (tests/hooks/test-cost-ledger-module.sh wraps it). The hooks beneath stand for the engine:
// session.usage answers the ledger, process.run is the append, turn.complete is core.

test('ledgerDelta: first reading, growth, no change, drop', () => {
  expect(ledgerDelta(undefined, 0.25)).toEqual({ delta: 0.25, reset: false })
  expect(ledgerDelta(0.25, 1)).toEqual({ delta: 0.75, reset: false })
  expect(ledgerDelta(1, 1)).toEqual({ delta: 0, reset: false })
  // A new process took over the session id and its ledger started again from zero.
  expect(ledgerDelta(3, 0.5)).toEqual({ delta: 0.5, reset: true })
})

type Usage = { cost?: { usd: number } } | 'throw'

const setup = (...[$, on]: Parameters<TestBody>) => {
  const h = {
    rows: [] as Record<string, unknown>[],
    logs: [] as string[],
    usage: { cost: { usd: 0 } } as Usage,
    fail: undefined as 'exit' | 'throw' | undefined,
    completes: 0,
  }
  on('session.id', () => ({ value: 's1' }))
  on('session.usage', () => {
    if (h.usage === 'throw') throw new Error('usage broke')
    return { value: { startedAt: 0, context: { window: 200000 }, rateLimits: [], ...h.usage } }
  })
  on('process.run', (_$, e) => {
    const mode = h.fail
    h.fail = undefined
    if (mode === 'throw') throw new Error('timed out')
    if (mode === undefined) for (const a of e.argv.slice(4)) h.rows.push(JSON.parse(String(a)))
    const exitCode = mode === 'exit' ? 1 : 0
    return { value: { exitCode, stdout: '', stderr: exitCode ? 'disk full' : '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.log', (_$, e) => (h.logs.push(e.text), { value: undefined }))
  on('turn.complete', () => (h.completes++, { text: 'core' }))
  const turn = (turnId: string, agentId?: string) =>
    $.turn.complete({ turnId, answer: '', durationMs: 0, isAborted: false, agentId, reason: 'answer' })
  return { h, turn }
}

test('records the cumulative ledger and the per-turn delta, main loop only', async ($, on) => {
  const { h, turn } = setup($, on)
  h.usage = { cost: { usd: 0.5 } }
  expect(await turn('t1')).toEqual({ text: 'core' })
  h.usage = { cost: { usd: 0.8 } }
  await turn('a1', 'agent-x') // a subagent's turn: no row, core still runs
  h.usage = { cost: { usd: 1.25 } }
  await turn('t2')
  h.usage = { cost: { usd: 0.1 } } // ledger restarted under the same session id
  await turn('t3')
  expect(h.rows.map(r => [r.session_id, r.turn_id, r.usd, r.delta, r.reset])).toEqual([
    ['s1', 't1', 0.5, 0.5, false],
    ['s1', 't2', 1.25, 0.75, false],
    ['s1', 't3', 0.1, 0.1, true],
  ])
  expect(h.completes).toBe(4)
  expect(typeof h.rows[0].t).toBe('string')
})

test('no cost on the usage: no row, core still runs', async ($, on) => {
  const { h, turn } = setup($, on)
  h.usage = {}
  expect(await turn('t1')).toEqual({ text: 'core' })
  expect(h.rows).toEqual([])
  expect(h.completes).toBe(1)
})

test('a throwing usage read becomes an error row, core still runs', async ($, on) => {
  const { h, turn } = setup($, on)
  h.usage = 'throw'
  expect(await turn('t1')).toEqual({ text: 'core' })
  expect(h.rows.length).toBe(1)
  expect(h.rows[0].session_id).toBe('s1')
  // The kit turns the throw beneath into "no implementation for session.usage".
  expect(String(h.rows[0].error)).toContain('session.usage')
  expect(h.rows[0].usd).toBeUndefined()
  // The failed read leaves the baseline alone: the next reading is still a first turn.
  h.usage = { cost: { usd: 0.4 } }
  await turn('t2')
  expect([h.rows[1].usd, h.rows[1].delta]).toEqual([0.4, 0.4])
  expect(h.completes).toBe(2)
})

// JSON.stringify writes NaN and both infinities as null, which the report once read as a $0 reset.
test('a non-finite reading becomes an error row and leaves the baseline alone', async ($, on) => {
  const { h, turn } = setup($, on)
  h.usage = { cost: { usd: 1 } }
  await turn('t1')
  h.usage = { cost: { usd: NaN } }
  expect(await turn('t2')).toEqual({ text: 'core' })
  h.usage = { cost: { usd: Infinity } }
  expect(await turn('t3')).toEqual({ text: 'core' })
  h.usage = { cost: { usd: 1.5 } }
  await turn('t4')
  expect(h.rows.map(r => [r.turn_id, r.usd, r.delta, r.reset])).toEqual([
    ['t1', 1, 1, false],
    ['t2', undefined, undefined, undefined],
    ['t3', undefined, undefined, undefined],
    ['t4', 1.5, 0.5, false],
  ])
  expect(String(h.rows[1].error)).toContain('non-finite')
  expect(String(h.rows[2].error)).toContain('non-finite')
  expect(h.completes).toBe(4)
})

test('a failed append is logged, never thrown, and core still runs', async ($, on) => {
  const { h, turn } = setup($, on)
  h.usage = { cost: { usd: 0.5 } }
  h.fail = 'exit'
  expect(await turn('t1')).toEqual({ text: 'core' })
  h.fail = 'throw'
  expect(await turn('t2')).toEqual({ text: 'core' })
  expect(h.completes).toBe(2)
  expect(h.logs.length).toBe(2)
  expect(h.logs[0]).toContain('disk full')
  // A lost row does not move the baseline: the next row carries the whole growth.
  h.usage = { cost: { usd: 0.9 } }
  await turn('t3')
  expect(h.rows.map(r => [r.turn_id, r.delta])).toEqual([['t3', 0.9]])
})
