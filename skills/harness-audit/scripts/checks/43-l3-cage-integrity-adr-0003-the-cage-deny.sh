# 43. L3 cage integrity (ADR 0003) — the cage-denylist + its guard are the single
# code-level bound on an unattended L3 run. If the cage is empty/missing, the guard
# is gone, or the cage stops covering a load-bearing safety surface, the loop could
# edit its own gates/audit/gauntlet and escape. Gated on ADR 0003 presence (other
# plugin repos + the audit fixtures don't declare L3, so the whole block is skipped).
# CRIT, not WARN: a holed cage is one model-version from a self-rewriting loop.
# RETIRED 2026-06-25 — L3-cage-integrity check retired (ADR 0006 supersedes 0003/0004/0005; the L3 autonomy machinery is deleted in Batch 2). The cage.txt FILE is kept (non-autonomy consumer); only this CHECK retires. ADRs are append-only, so the gate is no-op'd directly here rather than relying on ADR absence.
info "audit #43: RETIRED 2026-06-25 — L3-cage-integrity check retired (ADR 0006 supersedes 0003; cage.txt kept for non-autonomy consumer)" 2>/dev/null || true