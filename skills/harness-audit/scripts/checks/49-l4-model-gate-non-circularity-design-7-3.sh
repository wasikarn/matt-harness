# 49. L4 model-gate non-circularity (design §7, #30). The quality-gate is the one
# inferential surface allowed inside an armed run, so it MUST be structurally fail-
# closed + read-only. Positive assertions over scripts/l4/l4-quality-gate.sh:
#   (a) read-only: the default judge command grants no Write/Edit (mutation tools);
#   (b) fail-closed: a missing/unparseable verdict resolves to rollback (the *) case);
#   (c) veto-only: a red gauntlet short-circuits before any model call (never red→green);
#   (d) veto-green: a NOT_GOOD verdict forces rollback.
# RETIRED 2026-06-25 — L4 model-gate check retired (CLAUDE.md §The operating model (current) supersedes 0004; the L4 autonomy machinery is deleted in Batch 2). ADRs are append-only, so the gate is no-op'd directly here rather than relying on ADR absence.
info "audit #49: RETIRED 2026-06-25 — L4 model-gate non-circularity check retired (CLAUDE.md §The operating model (current) supersedes 0004; L4 machinery deleted in Batch 2)" 2>/dev/null || true