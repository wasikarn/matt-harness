# 52. review_finding rigor provenance — the push gate (Gate 2, ADR 0003/0004/0005)
# authorizes an armed push when KBG_REVIEW_DONE=1 AND a `review_finding` event is in
# the last 500 journal lines. That check is *presence*, not *rigor*: a single
# operator-authored inline-review verdict satisfies the gate IDENTICALLY to a full
# multi-agent kbg:review-pr. This check was OBSERVE-FLAG only (INFO, never inflates
# the audit exit code) so a decay sweep can verify inline-agent review_findings were
# justified, not silently rubber-stamp armed pushes.
# RETIRED 2026-06-25 — Gate-2 (push-gate.sh) is gone (ADR 0006 supersedes 0003/0004/0005; push-gate retired in Batch 2), so the rubber-stamp surface is moot. ADRs are append-only, so the gate is no-op'd directly here rather than relying on ADR absence.
info "audit #52: RETIRED 2026-06-25 — review-finding-rigor surface retired (Gate-2 gone; ADR 0006 supersedes 0003/0004/0005)" 2>/dev/null || true