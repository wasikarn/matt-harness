# 48. L4 F1 floor — fires under the flag AND stays byte-identical flag-off (design
# §5 #48, CLAUDE.md §The operating model (was L4 self-launch, retired)). The single-key autonomy_on() collapse is exactly the refactor
# that can regress the flag-OFF path via empty-string truthiness / a wrong default,
# so this check PROVES both directions instead of asserting them in prose. Gated on
# CLAUDE.md §The operating model (was L4 self-launch, retired) presence. Three legs:
#   (a) armed (per-repo KBG_AUTONOMY=1, no L5 allowlist, no KBG_REVIEW_DONE) → the
#       push gate DENIES a real git push;
#   (b) flag unset → the push gate no-ops (exit 0) as the L2 baseline;
#   (c) enumeration — every arming read routes through autonomy_on(): CRIT on a raw
#       KBG_AUTONOMY literal outside the sanctioned homes, and on any LEFTOVER legacy
#       KBG_AUTONOMY_L3 / KBG_L3_REVIEW_DONE in active code.
# RETIRED 2026-06-25 — 48a/48b push-gate runtime probes were removed in 7cabcea; 48c/48d now retire with autonomy_on (CLAUDE.md §The operating model (current) supersedes 0004; L4 machinery deleted in Batch 2). ADRs are append-only, so the gate is no-op'd directly here rather than relying on ADR absence.
info "audit #48: RETIRED 2026-06-25 — 48c/48d retired with autonomy_on (CLAUDE.md §The operating model (current) supersedes 0004; L4 machinery deleted in Batch 2)" 2>/dev/null || true