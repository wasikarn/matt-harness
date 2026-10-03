import type { Register } from 'claude-code'

// mh's one hooks module (GH #323, #334): an observer that records Claude Code's own cost ledger
// ($.session.usage().cost.usd, what /cost totals) after each main-loop turn, so cost-report can
// cross-check the transcript-priced costs.jsonl against it. Reference:
// docs/reference/cost-ledger-module.md.
//
// Observer only: it never denies, asks, rewrites or answers for core. Every step sits in one
// try/catch and the hook always ends in `next(e)`, so a failure here costs one row, never the turn.
// The engine also skips a hook that throws, but this one does not rely on that.
//
// $.fs has no append, so a one-line `sh` appends the row (dotfiles effort-log's pattern); $HOME
// expands inside that shell, and `${HOME:?}` makes an unset HOME fail instead of writing under `/`.
const APPEND =
  ': "${HOME:?HOME unset}"; d="$HOME/.local/share/kbg/metrics"; mkdir -p "$d" && printf "%s\\n" "$@" >> "$d/cost-ledger.jsonl"'

// The ledger only grows inside one process. A drop means a new process took over the session id
// and started its ledger from zero, so everything it shows is new spend. The report applies the
// same rule to the file's `usd` sequence (skills/meta/cost-report/scripts/cost-report-dedup.js).
export const ledgerDelta = (prev: number | undefined, usd: number) =>
  prev === undefined || usd >= prev
    ? { delta: usd - (prev ?? 0), reset: false }
    : { delta: usd, reset: true }

// ponytail: the baseline is a module variable, so a reload (/reload-plugins, a settings change)
// restarts it and that load's first row reads `delta == usd`. The report recomputes from `usd`,
// so totals stay right; move it to $.state (needs a types contract in plugin.json) if per-row
// deltas start to matter.
let prev: number | undefined

export const register: Register = on => {
  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) return next(e)
    let session = 'unknown'
    let row: string | undefined
    let usd: number | undefined
    try {
      session = await $.session.id()
      const u = (await $.session.usage()).cost?.usd
      // JSON.stringify writes NaN/Infinity as null; throwing here makes it an error row and keeps
      // `usd` undefined, so the baseline below is not set to NaN.
      if (typeof u === 'number' && !Number.isFinite(u)) throw new Error(`non-finite ledger usd: ${u}`)
      usd = u
      if (typeof usd === 'number') {
        const { delta, reset } = ledgerDelta(prev, usd)
        row = JSON.stringify({ t: new Date().toISOString(), session_id: session, turn_id: e.turnId, usd, delta, reset })
      }
    } catch (err) {
      row = JSON.stringify({ t: new Date().toISOString(), session_id: session, turn_id: e.turnId, error: String(err).slice(0, 200) })
    }
    if (row !== undefined) {
      try {
        const r = await $.process.run(['sh', '-c', APPEND, 'sh', row], { timeoutMs: 2000 })
        if (r.exitCode !== 0) $.ui.log(`cost-ledger append exited ${r.exitCode}: ${r.stderr.trim().slice(0, 200)}`)
        else if (usd !== undefined) prev = usd
      } catch (err) {
        $.ui.log(`cost-ledger append failed: ${String(err).slice(0, 200)}`)
      }
    }
    return next(e)
  })
}
