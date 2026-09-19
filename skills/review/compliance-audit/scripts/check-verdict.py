#!/usr/bin/env python3
"""Validate a dispatched compliance-audit verifier's return value and compute `pass`.

Mirrors mh:deep-audit's scripts/check-verdict.py (same NEEDS-DECISION escape hatch,
same brace-scanning, same ambiguity handling) for compliance-audit's own contract:
references/verifier-output-schema.json. Used on both paths — pipe Codex's
--output-last-message file through this too, not just the Claude-fallback path,
because Codex's --output-schema only guarantees the verifier's JSON matches the
schema; it does not compute `pass`. This script is the only place `pass` is ever
computed: SKILL.md's own rule ("`pass` is never true on requirements alone") is
transcribed here so no hand-eyeballed reconciliation ever reaches the report.

stdin: the verifier's raw final message text (Codex --output-last-message file
contents, or the Claude-fallback agent's final message).

Behavior:
  - A literal `NEEDS-DECISION` anywhere in the text wins over any JSON found nearby,
    same rule as deep-audit's script and for the same reason: the contract is a
    verdict object OR an escalation, never both.
  - Scans every '{' in the text and keeps every candidate that fully validates
    against the schema (exact key-set equality) AND the semantic rule below.
    Exactly one valid candidate is required; two or more distinct ones reject as
    ambiguous.
  - Semantic rule beyond the JSON Schema: `accepted` must be a bool when
    `verdict == "DEVIATED"` (was it sanctioned or not — null is not an answer for
    a requirement that actually deviated) and must be null otherwise (CONFORMS/
    MISSING don't have an acceptance question to answer).
  - Computes `pass` per SKILL.md Core Principles: every requirement is CONFORMS or
    an accepted DEVIATED, AND gauntlet.exit_code == 0, AND scope_ok is true. A
    verifier-supplied `pass` field is never read — this script is the only
    arithmetic, same reason weighted-score.py is the only place a score total is
    computed.

Exit codes: 0 = exactly one valid verdict (printed to stdout as JSON, with `pass`
added); 1 = malformed, rejected, or ambiguous (reason on stderr, nothing on
stdout — never reaches Phase 3's report); 2 = NEEDS-DECISION escalation.
"""
import json
import re
import sys

REQUIRED_KEYS = {"requirements", "gauntlet", "scope_ok", "unexpected_files"}
REQUIREMENT_KEYS = {"id", "verdict", "note", "accepted"}
GAUNTLET_KEYS = {"command", "sha", "exit_code", "output_tail"}
VERDICTS = {"CONFORMS", "DEVIATED", "MISSING"}


def extract_object(text):
    dec = json.JSONDecoder()
    i = text.find("{")
    while i != -1:
        try:
            obj, _ = dec.raw_decode(text, i)
            return obj
        except ValueError:
            i = text.find("{", i + 1)
    return None


def extract_valid_candidates(text):
    dec = json.JSONDecoder()
    seen = {}
    i = text.find("{")
    while i != -1:
        try:
            obj, _ = dec.raw_decode(text, i)
        except ValueError:
            i = text.find("{", i + 1)
            continue
        if isinstance(obj, dict) and validate(obj)[0]:
            seen[json.dumps(obj, sort_keys=True)] = obj
        i = text.find("{", i + 1)
    return list(seen.values())


def validate(obj):
    """Return (ok, reason). reason names what was rejected when not ok."""
    if not isinstance(obj, dict):
        return False, "top-level value is not an object"
    if set(obj.keys()) != REQUIRED_KEYS:
        extra = set(obj.keys()) - REQUIRED_KEYS
        missing = REQUIRED_KEYS - set(obj.keys())
        return False, f"key set mismatch: extra={sorted(extra)} missing={sorted(missing)}"

    reqs = obj["requirements"]
    if not isinstance(reqs, list):
        return False, "'requirements' is not a list"
    for idx, r in enumerate(reqs):
        if not isinstance(r, dict) or set(r.keys()) != REQUIREMENT_KEYS:
            return False, f"requirements[{idx}] is not exactly {{id, verdict, note, accepted}}: {r!r}"
        if not isinstance(r.get("id"), str) or not isinstance(r.get("note"), str):
            return False, f"requirements[{idx}].id/note must be strings: {r!r}"
        if r.get("verdict") not in VERDICTS:
            return False, f"requirements[{idx}].verdict must be one of {sorted(VERDICTS)}: {r!r}"
        accepted = r.get("accepted")
        if r["verdict"] == "DEVIATED":
            if not isinstance(accepted, bool):
                return False, f"requirements[{idx}] is DEVIATED but 'accepted' is not a boolean: {r!r}"
        elif accepted is not None:
            return False, f"requirements[{idx}] is {r['verdict']} but 'accepted' is not null: {r!r}"

    gauntlet = obj["gauntlet"]
    if not isinstance(gauntlet, dict) or set(gauntlet.keys()) != GAUNTLET_KEYS:
        return False, f"'gauntlet' is not exactly {{command, sha, exit_code, output_tail}}: {gauntlet!r}"
    if not isinstance(gauntlet.get("command"), str) or not isinstance(gauntlet.get("sha"), str) \
            or not isinstance(gauntlet.get("output_tail"), str):
        return False, f"gauntlet.command/sha/output_tail must be strings: {gauntlet!r}"
    if not isinstance(gauntlet.get("exit_code"), int) or isinstance(gauntlet.get("exit_code"), bool):
        return False, f"gauntlet.exit_code must be an integer: {gauntlet!r}"

    if not isinstance(obj["scope_ok"], bool):
        return False, f"'scope_ok' is not a boolean: {obj['scope_ok']!r}"
    if not isinstance(obj["unexpected_files"], list) or not all(
        isinstance(x, str) for x in obj["unexpected_files"]
    ):
        return False, "'unexpected_files' is not a list of strings"

    return True, ""


def compute_pass(obj):
    """SKILL.md Core Principles, transcribed: pass requires every requirement
    CONFORMS or accepted-DEVIATED, AND the gauntlet exits 0, AND scope_ok."""
    reqs_ok = all(
        r["verdict"] == "CONFORMS" or (r["verdict"] == "DEVIATED" and r["accepted"] is True)
        for r in obj["requirements"]
    )
    return bool(reqs_ok and obj["gauntlet"]["exit_code"] == 0 and obj["scope_ok"])


def main():
    text = sys.stdin.read()
    match = re.search(r"NEEDS-DECISION\b.*", text)
    if match:
        print(match.group(0).strip())
        print("check-verdict: escalation (NEEDS-DECISION), not a malformed verdict", file=sys.stderr)
        return 2
    candidates = extract_valid_candidates(text)
    if len(candidates) == 1:
        result = dict(candidates[0])
        result["pass"] = compute_pass(result)
        json.dump(result, sys.stdout, indent=2)
        print()
        return 0
    if len(candidates) > 1:
        print(f"check-verdict: rejected — {len(candidates)} distinct schema-valid "
              "verdict objects found in the same message; ambiguous, refusing to guess",
              file=sys.stderr)
        return 1
    obj = extract_object(text)
    if obj is not None:
        _, reason = validate(obj)
        print(f"check-verdict: rejected — {reason}", file=sys.stderr)
        return 1
    print("check-verdict: rejected — no parseable JSON object and no NEEDS-DECISION found", file=sys.stderr)
    return 1


def _selftest():
    import io
    import contextlib

    def run(text):
        buf_out, buf_err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(buf_out), contextlib.redirect_stderr(buf_err):
            old_stdin = sys.stdin
            sys.stdin = io.StringIO(text)
            try:
                code = main()
            finally:
                sys.stdin = old_stdin
        return code, buf_out.getvalue(), buf_err.getvalue()

    good = json.dumps({
        "requirements": [
            {"id": "R1", "verdict": "CONFORMS", "note": "", "accepted": None},
            {"id": "R2", "verdict": "DEVIATED", "note": "renamed field", "accepted": True},
        ],
        "gauntlet": {"command": "bash gauntlet.sh", "sha": "abc123", "exit_code": 0, "output_tail": "ok"},
        "scope_ok": True,
        "unexpected_files": [],
    })
    code, out, err = run(good)
    parsed = json.loads(out)
    assert code == 0 and parsed["pass"] is True, (code, out, err)

    unaccepted = json.loads(good)
    unaccepted["requirements"][1]["accepted"] = False
    code, out, err = run(json.dumps(unaccepted))
    parsed = json.loads(out)
    assert code == 0 and parsed["pass"] is False, (code, out, err)

    missing_req = json.loads(good)
    missing_req["requirements"].append({"id": "R3", "verdict": "MISSING", "note": "", "accepted": None})
    code, out, err = run(json.dumps(missing_req))
    parsed = json.loads(out)
    assert code == 0 and parsed["pass"] is False, (code, out, err)

    bad_gauntlet = json.loads(good)
    bad_gauntlet["gauntlet"]["exit_code"] = 1
    code, out, err = run(json.dumps(bad_gauntlet))
    parsed = json.loads(out)
    assert code == 0 and parsed["pass"] is False, (code, out, err)

    scope_bad = json.loads(good)
    scope_bad["scope_ok"] = False
    code, out, err = run(json.dumps(scope_bad))
    parsed = json.loads(out)
    assert code == 0 and parsed["pass"] is False, (code, out, err)

    # Semantic rule: DEVIATED requires a real boolean 'accepted', not null.
    deviated_null = json.loads(good)
    deviated_null["requirements"][1]["accepted"] = None
    code, out, err = run(json.dumps(deviated_null))
    assert code == 1 and "accepted" in err, (code, out, err)

    # Semantic rule: CONFORMS/MISSING must have 'accepted' null, not a stray bool.
    conforms_bool = json.loads(good)
    conforms_bool["requirements"][0]["accepted"] = True
    code, out, err = run(json.dumps(conforms_bool))
    assert code == 1 and "accepted" in err, (code, out, err)

    extra_field = json.loads(good)
    extra_field["notes"] = "extra"
    code, out, err = run(json.dumps(extra_field))
    assert code == 1 and "key set mismatch" in err, (code, out, err)

    bad_verdict = json.loads(good)
    bad_verdict["requirements"][0]["verdict"] = "PARTIAL"
    code, out, err = run(json.dumps(bad_verdict))
    assert code == 1 and "verdict must be one of" in err, (code, out, err)

    escalation = "I can't determine this safely.\nNEEDS-DECISION is the plan's SHA still resolvable?"
    code, out, err = run(escalation)
    assert code == 2 and out.strip().startswith("NEEDS-DECISION"), (code, out, err)

    # Decoy ahead of the real, differently-valued verdict must be rejected as ambiguous.
    decoy = json.loads(good)
    decoy["scope_ok"] = False
    code, out, err = run(f"Example shape: {json.dumps(decoy)}\nActual result: {good}")
    assert code == 1 and "ambiguous" in err and out == "", (code, out, err)

    print("check-verdict.py (compliance-audit) selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
    else:
        sys.exit(main())
