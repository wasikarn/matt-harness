#!/usr/bin/env python3
"""Validate a dispatched validator/checker's verdict on the Claude fallback path.

Used when mh:deep-audit's Codex checker is unavailable and SKILL.md dispatches
a Claude Explore/review agent instead (see SKILL.md step 3, "On any other
outcome"). That agent has no --output-schema enforcement, so this script is
the only shape check its return value gets.

stdin: the dispatched agent's raw final message text.

Behavior:
  - Extracts the first JSON object in the text that actually parses, trying
    every '{' in order (not just the first byte) -- narration before the real
    JSON can itself contain a brace, e.g. the agent echoing
    docs/reference/spawn-brief.md's own return-contract line.
  - Validates it against the exact contract docs/reference/spawn-brief.md and
    references/checker-output-schema.json both state: {pass, findings[],
    scope_ok, unexpected_files[]} and nothing else. `pass`/`scope_ok` must be
    real booleans; `findings[]` items must be exactly {summary, evidence}
    (both strings); `unexpected_files[]` must be a list of strings.
  - A message that instead carries `NEEDS-DECISION` (docs/reference/
    spawn-brief.md's escalation return) with no parseable verdict object is a
    valid non-guess, not a malformed one -- reported as a distinct outcome.

Exit codes: 0 = valid verdict (printed to stdout as JSON); 1 = malformed or
rejected (reason on stderr, nothing on stdout -- never reaches a fixer
brief); 2 = NEEDS-DECISION escalation, no verdict object (the question, if
found, on stdout; noted on stderr).
"""
import json
import re
import sys

REQUIRED_KEYS = {"pass", "findings", "scope_ok", "unexpected_files"}
FINDING_KEYS = {"summary", "evidence"}


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


def validate(obj):
    """Return (ok, reason). reason names what was rejected when not ok."""
    if not isinstance(obj, dict):
        return False, "top-level value is not an object"
    if set(obj.keys()) != REQUIRED_KEYS:
        extra = set(obj.keys()) - REQUIRED_KEYS
        missing = REQUIRED_KEYS - set(obj.keys())
        return False, f"key set mismatch: extra={sorted(extra)} missing={sorted(missing)}"
    if not isinstance(obj["pass"], bool):
        return False, f"'pass' is not a boolean: {obj['pass']!r}"
    if not isinstance(obj["scope_ok"], bool):
        return False, f"'scope_ok' is not a boolean: {obj['scope_ok']!r}"
    if not isinstance(obj["findings"], list):
        return False, "'findings' is not a list"
    for idx, f in enumerate(obj["findings"]):
        if not isinstance(f, dict) or set(f.keys()) != FINDING_KEYS:
            return False, f"findings[{idx}] is not exactly {{summary, evidence}}: {f!r}"
        if not isinstance(f.get("summary"), str) or not isinstance(f.get("evidence"), str):
            return False, f"findings[{idx}].summary/evidence must be strings: {f!r}"
    if not isinstance(obj["unexpected_files"], list) or not all(
        isinstance(x, str) for x in obj["unexpected_files"]
    ):
        return False, "'unexpected_files' is not a list of strings"
    return True, ""


def main():
    text = sys.stdin.read()
    obj = extract_object(text)
    if obj is not None:
        ok, reason = validate(obj)
        if ok:
            json.dump(obj, sys.stdout, indent=2)
            print()
            return 0
        print(f"check-verdict: rejected — {reason}", file=sys.stderr)
        return 1
    match = re.search(r"NEEDS-DECISION\b.*", text)
    if match:
        print(match.group(0).strip())
        print("check-verdict: escalation (NEEDS-DECISION), not a malformed verdict", file=sys.stderr)
        return 2
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

    good = json.dumps({"pass": True, "findings": [], "scope_ok": True, "unexpected_files": []})
    code, out, err = run(good)
    assert code == 0 and json.loads(out) == json.loads(good), (code, out, err)

    extra_field = json.dumps({"pass": True, "findings": [], "scope_ok": True,
                               "unexpected_files": [], "notes": "extra"})
    code, out, err = run(extra_field)
    assert code == 1 and "key set mismatch" in err, (code, out, err)

    pass_as_string = json.dumps({"pass": "mostly", "findings": [], "scope_ok": True,
                                  "unexpected_files": []})
    code, out, err = run(pass_as_string)
    assert code == 1 and "'pass' is not a boolean" in err, (code, out, err)

    scope_ok_null = json.dumps({"pass": True, "findings": [], "scope_ok": None,
                                 "unexpected_files": []})
    code, out, err = run(scope_ok_null)
    assert code == 1 and "'scope_ok' is not a boolean" in err, (code, out, err)

    bad_finding = json.dumps({"pass": False,
                               "findings": [{"issue": "x", "sev": "high"}],
                               "scope_ok": True, "unexpected_files": []})
    code, out, err = run(bad_finding)
    assert code == 1 and "findings[0]" in err, (code, out, err)

    # Narration echoing the return contract's own brace before the real JSON.
    echoed = ('Return {pass, findings[], scope_ok, unexpected_files[]} as instructed.\n'
              + good)
    code, out, err = run(echoed)
    assert code == 0 and json.loads(out) == json.loads(good), (code, out, err)

    escalation = "I can't determine this safely.\nNEEDS-DECISION does file X own behavior Y?"
    code, out, err = run(escalation)
    assert code == 2 and out.strip().startswith("NEEDS-DECISION"), (code, out, err)
    assert "escalation" in err

    print("check-verdict.py selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
    else:
        sys.exit(main())
