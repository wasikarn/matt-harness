#!/usr/bin/env python3
"""Citation-shape check for idea-audit attacker output.

Found by the 2026-09-19 criteria-quality audit: SKILL.md and attacker-brief.md
both described this as something "the host checks" by eye -- schema validity
alone only proves `evidence` is a non-empty string, not a real citation. This
script makes that check mechanical. Run it AFTER schema/pass/checked-presence
validation (already enforced by --output-schema or a manual parse) -- it does
not re-validate the envelope, only the citation shape inside each `evidence`.

stdin: the attacker's already schema-valid JSON (see attacker-output-schema.json).

A citation shape is: a backticked span `...` (a command), OR a path-like token
(contains "/" or ".") immediately followed by ":<digits>" -- a path:line cite,
or the path:line prefix of a grep -n style "path:line:content" excerpt.

Exit 0: every findings[]/checked[] evidence string has a citation shape --
nothing on stdout, matching the gauntlet's own quiet-on-success convention.
Exit 1: at least one evidence string fails -- each failing item printed to
stderr as "{findings|checked}[i]: <evidence text>". Per SKILL.md, a failing
item is treated the same as a missing citation for Phase 3's scoring, not a
reason to reject the whole attacker run by itself.
"""
import json
import re
import sys

CITATION_RE = re.compile(r"`[^`]+`|[^\s:`]*[./][^\s:`]*:\d+")


def has_citation(evidence):
    return bool(CITATION_RE.search(evidence))


def main():
    obj = json.load(sys.stdin)
    failures = []
    for i, f in enumerate(obj.get("findings", [])):
        if not has_citation(f.get("evidence", "")):
            failures.append(f"findings[{i}]: {f.get('evidence', '')!r}")
    for i, c in enumerate(obj.get("checked", [])):
        if not has_citation(c.get("evidence", "")):
            failures.append(f"checked[{i}]: {c.get('evidence', '')!r}")
    if failures:
        print("check-citations: rejected — evidence missing a citation shape "
              "(backticked command, or path:line):", file=sys.stderr)
        for line in failures:
            print(f"  {line}", file=sys.stderr)
        return 1
    return 0


def _selftest():
    import io
    import contextlib

    def run(obj):
        buf_out, buf_err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(buf_out), contextlib.redirect_stderr(buf_err):
            old_stdin = sys.stdin
            sys.stdin = io.StringIO(json.dumps(obj))
            try:
                code = main()
            finally:
                sys.stdin = old_stdin
        return code, buf_out.getvalue(), buf_err.getvalue()

    # path:line citation.
    code, out, err = run({"findings": [{"summary": "s", "evidence": "skills/foo/bar.py:42"}],
                           "checked": []})
    assert code == 0 and out == "" and err == "", (code, out, err)

    # backticked command citation.
    code, out, err = run({"findings": [],
                           "checked": [{"claim": "c", "evidence": "ran `git log --oneline -5`"}]})
    assert code == 0, (code, out, err)

    # grep -n style excerpt (path:line:content).
    code, out, err = run({"findings": [],
                           "checked": [{"claim": "c",
                                        "evidence": "src/app.py:10:    def foo():"}]})
    assert code == 0, (code, out, err)

    # bare prose, no citation shape -- must fail.
    code, out, err = run({"findings": [{"summary": "s", "evidence": "it looks fine to me"}],
                           "checked": []})
    assert code == 1 and "findings[0]" in err, (code, out, err)

    # a time-of-day string must NOT false-match as a path:line citation.
    code, out, err = run({"findings": [],
                           "checked": [{"claim": "c", "evidence": "the run finished at 3:00"}]})
    assert code == 1 and "checked[0]" in err, (code, out, err)

    # checked[] failure reported independently of findings[] passing.
    code, out, err = run({"findings": [{"summary": "s", "evidence": "docs/x.md:1"}],
                           "checked": [{"claim": "c", "evidence": "trust me"}]})
    assert code == 1 and "checked[0]" in err and "findings[0]" not in err, (code, out, err)

    print("check-citations.py selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
    else:
        sys.exit(main())
