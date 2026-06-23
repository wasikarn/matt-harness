# 52. review_finding rigor provenance — the push gate (Gate 2, ADR 0003/0004/0005)
# authorizes an armed push when KBG_REVIEW_DONE=1 AND a `review_finding` event is in
# the last 500 journal lines (push-gate.sh:87). That check is *presence*, not *rigor*:
# a single operator-authored inline-review verdict (fields.agent = "inline-review …",
# no fresh-context pass) satisfies the gate IDENTICALLY to a full multi-agent
# kbg:review-pr (fields.agent = "kbg:code-reviewer" / "kbg:security-reviewer" / …).
# The gate certifies "a review was journaled," not "a maker≠checker review happened."
# This check does NOT change the gate (the floor stays permissive — hardening it to
# enforce-deny would trip the #31.1 ceremony trap: forcing a multi-agent pass on every
# armed push, including a one-line doc diff). It is OBSERVE-FLAG only: surface
# inline-agent review_findings so a decay sweep can verify they were justified, not
# silently rubber-stamp armed pushes. INFO (not WARN) — it never inflates the audit
# exit code or breaks a 0C/0W clean run; the maker≠checker bar stays step 2 of the
# armed-push dance (memory `armed-push-review-path`), the gate is the floor not the
# ceiling. Gated on the addendum ADR; skip cleanly if it or the journal is absent.
# See docs/adr/0002-addendum-push-gate-review-rigor.md.
ADR52="$CLAUDE_DIR/docs/adr/0002-addendum-push-gate-review-rigor.md"
if [ -f "$ADR52" ]; then
  _J52="${CLAUDE_JOURNAL_PATH:-$HOME/.claude/governance-events.jsonl}"
  if [ -f "$_J52" ]; then
    _n52=$(python3 - "$_J52" <<'PY' 2>/dev/null || printf 0
import json, sys
path = sys.argv[1]
# Dispatched reviewer agents (the fleet routed by skills/review-pr/SKILL.md
# Phase 3). Recorded under either a bare name or a kbg:-namespaced form, and
# combined multi-agent reviews are joined with '+'. A review_finding whose
# agent is NOT composed entirely of these names (e.g. "inline-review …",
# "orchestrator", "x", blank) was NOT produced by a dispatched fresh-context
# reviewer — i.e. not maker≠checker. SSOT for the set = review-pr Phase 3
# routing; keep in sync when a reviewer agent is added/renamed.
reviewers = {
    "code-reviewer", "security-reviewer", "silent-failure-hunter",
    "pr-test-analyzer", "comment-analyzer", "type-design-analyzer",
    "ux-reviewer",
}
n = 0
with open(path, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("event") != "review_finding":
            continue
        agent = ((d.get("fields") or {}).get("agent") or "").strip()
        # Tokenize multi-agent forms on '+', strip an optional kbg: prefix,
        # and require EVERY token to be a known reviewer name. Any unknown
        # token (inline/operator/test/blank) → not maker≠checker.
        tokens = [t.strip().removeprefix("kbg:") for t in agent.split("+")]
        if not tokens or not all(t in reviewers for t in tokens):
            n += 1
print(n)
PY
    )
    if [ "${_n52:-0}" -gt 0 ]; then
      info "audit #52: ${_n52} review_finding event(s) whose agent is not a dispatched reviewer (fields.agent not composed of fleet reviewer names) — not maker≠checker; may have justified an armed push. Verify at the decay sweep (push-gate rubber-stamp surface; ADR 0002 addendum)."
    fi
  fi
fi