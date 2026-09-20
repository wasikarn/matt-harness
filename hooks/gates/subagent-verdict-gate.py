#!/usr/bin/env python3
# gate:agent:subagent-verdict-check -- Tier 1 of the "auto-apply the attacker
# pattern via hooks?" design note (docs/research/
# nine-agent-gate-architecture-security-audit-2026-09-20.md, "Design note"
# section). A SubagentStop hook that mechanically catches a vacuous or
# self-contradictory Rule 13 verdict object -- {"pass":true,"findings":[],
# "scope_ok":true,"unexpected_files":[]} is schema-valid but shows no
# verification work, the exact gap `checked[]` closes in prose (spawn-brief.md,
# METHODOLOGY.md) and in the 3 sibling skills' own check-verdict.py scripts.
# This makes the same rule apply automatically to every OTHER Rule 13 dispatch,
# which today has no check-verdict.py-equivalent at all (confirmed 2026-09-20:
# zero file-based consumers parse the generic contract programmatically).
#
# Stateless by design (no cross-call bookkeeping): the loop bound is the
# `stop_hook_active` field Claude Code already puts on the payload for
# exactly this loop-prevention purpose, read below, not a counter kept here --
# adding one would be the exact session-scoped-round-counter shape #135/#137
# already rejected.
#
# Fail-open posture matches this repo's other subagent-scoped gates
# (subagent-git-guard, subagent-spawn-guard, task-complete-separation): the
# "verdict" here only optimizes a check that would not otherwise run at all,
# it never authorizes an irrecoverable action, so any internal failure must
# fall through to the native no-hook-installed behavior (let the subagent
# stop), never block. Per operating-model.md's stated principle: "fail open
# to the native/no-op path when the verdict only optimizes one that was
# already going to happen anyway."
import json
import sys
from typing import NoReturn

try:
    from _journal import journal
except Exception:
    def journal(*a, **k):
        pass

GATE_ID = "gate:agent:subagent-verdict-check"


def _allow(note=None) -> NoReturn:
    if note:
        print(f"[mh:gate] subagent-verdict-check: {note}", file=sys.stderr)
    sys.exit(0)


def _find_json_dicts(text):
    # String-aware brace matching: for each '{', walk forward tracking quote
    # state so a '{'/'}' inside a JSON string value never miscounts depth,
    # then try json.loads on the exact balanced span. Nested spans (e.g. one
    # findings[] item's own {summary, evidence} object) are found too but
    # filtered out downstream by the "has a bool `pass` key" check -- they
    # parse fine on their own, they just aren't the verdict object.
    out = []
    n = len(text)
    i = 0
    while i < n:
        if text[i] == "{":
            depth = 0
            in_str = False
            esc = False
            j = i
            while j < n:
                c = text[j]
                if in_str:
                    if esc:
                        esc = False
                    elif c == "\\":
                        esc = True
                    elif c == '"':
                        in_str = False
                else:
                    if c == '"':
                        in_str = True
                    elif c == "{":
                        depth += 1
                    elif c == "}":
                        depth -= 1
                        if depth == 0:
                            try:
                                obj = json.loads(text[i:j + 1])
                                if isinstance(obj, dict):
                                    out.append(obj)
                            except Exception:
                                pass
                            break
                j += 1
        i += 1
    return out


try:
    d = json.load(sys.stdin)
except Exception as e:
    _allow(f"unparseable stdin, allowing ({e})")

if not isinstance(d, dict):
    _allow("non-object payload, allowing")

if d.get("hook_event_name") != "SubagentStop":
    sys.exit(0)

if d.get("stop_hook_active") is True:
    # Already re-prompted once this stop; never block a second time in a row.
    sys.exit(0)

msg = d.get("last_assistant_message")
if not isinstance(msg, str) or not msg.strip():
    sys.exit(0)

if len(msg) > 200_000:
    # ponytail: brace-rescan below is O(n*braces); a message this long is not
    # an ordinary verdict reply anyway. Skip the check rather than risk the
    # 8s timeout (fail-open on timeout is safe here, but cheaper to just skip).
    sys.exit(0)

# A subagent that correctly declined to guess is never a vacuous pass --
# this is a valid, non-guessing response and must never be blocked
# (spawn-brief.md's own escalation return; same precedent every
# check-verdict.py script in this repo already follows).
if "NEEDS-DECISION" in msg:
    sys.exit(0)

try:
    candidates = _find_json_dicts(msg)
    verdicts = [c for c in candidates if isinstance(c.get("pass"), bool)]
except Exception as e:
    _allow(f"verdict-scan crashed, allowing ({e})")

if len(verdicts) == 0:
    # Not a Rule 13 verdict-shaped response at all (most subagents: Explore,
    # research, code-architect building something) -- nothing to check.
    sys.exit(0)

if len(verdicts) > 1:
    # Two or more distinct pass-bearing objects (a decoy example quoted
    # ahead of the real verdict) -- ambiguous. Never block on uncertainty;
    # this mirrors check-verdict.py's own "reject as ambiguous" rule, but a
    # hook's only two moves are allow/block, and blocking on genuine
    # ambiguity risks false-positive friction on ordinary prose that happens
    # to quote a JSON example. Allow, noted for visibility.
    _allow(f"{len(verdicts)} distinct pass-bearing objects found, ambiguous -- allowing without a check")

v = verdicts[0]
reasons = []

if v.get("pass") is True:
    checked = v.get("checked")
    findings = v.get("findings")
    checked_empty = not isinstance(checked, list) or len(checked) == 0
    findings_empty = not isinstance(findings, list) or len(findings) == 0
    if checked_empty and findings_empty:
        reasons.append(
            "pass:true but no findings[] and no checked[] evidence -- cite at least one "
            "checkable fact (a file:line you read, a command you ran) in checked[] even on "
            "a clean pass; an empty checked[] is not verified, same as a missing field "
            "(docs/reference/spawn-brief.md, docs/METHODOLOGY.md Rule 13)"
        )
    if v.get("scope_ok") is False:
        reasons.append(
            "pass:true but scope_ok:false -- these are self-contradictory; scope_ok:false "
            "means an unexpected file or an owned file the diff never touched, which cannot "
            "coexist with an overall pass"
        )
    unexpected = v.get("unexpected_files")
    if isinstance(unexpected, list) and len(unexpected) > 0:
        reasons.append(
            f"pass:true but unexpected_files has {len(unexpected)} entr"
            + ("y" if len(unexpected) == 1 else "ies")
            + " -- reconcile or explain the scope mismatch before reporting pass"
        )

if not reasons:
    sys.exit(0)

reason_text = (
    "Your returned verdict is self-contradictory or vacuous: "
    + "; ".join(reasons)
    + ". Re-check your own work and return a corrected verdict object with real evidence, "
      "not a redo of the same claim."
)
journal(GATE_ID, d.get("agent_type"), "deny", d.get("session_id"))
print(json.dumps({"decision": "block", "reason": reason_text}))
sys.exit(0)
