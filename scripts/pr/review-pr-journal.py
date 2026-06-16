#!/usr/bin/env python3
"""
review-pr-journal — emit Phase-II review_finding + verification_verdict pairs
from a /review-pr scratch dir's findings.jsonl. Idempotent via a per-finding
JSONL manifest (.journaled). Port of review-pr-journal.sh (232 LoC); the
contract is the 11 test cases (M, N, N2, P, R, S, T, U, V, W, X, Y) pinned
at claude/hooks/tests/test-critical-hooks.sh:333-739.

Usage: review-pr-journal.py <scratch_dir>
  scratch_dir/findings.jsonl — per-finding JSONL stream, one finding per line
  scratch_dir/.journaled     — per-pair manifest (one JSONL line per emitted pair)

Exit codes: 0 success OR no-op; 2 fail-loud (bad arg count, missing
findings.jsonl, malformed .journaled manifest, fields_json invalid in
_lib.journal_append).
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

# Repo-local import — works when invoked as `python3 scripts/pr/review-pr-journal.py`
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "hooks"))
import _lib  # noqa: E402

HOOK_ID = "review-pr-journaler"

# Enum-typed fields per JOURNAL-SCHEMA.md § "review_finding + verification_verdict".
# Stays in lockstep with JOURNAL-SCHEMA.md. Empty tier is allowed (review-body
# findings have no file:line/tier); disposition/decision are the SCRUTINIZE-4
# ground truth, so a miss there is a WARNING to stderr and the journal still
# emits (Q3=a "silent FYI, never unwinds" — the journaler is best-effort, not
# a gate).
TIER_OK = re.compile(r"^(Critical|Important|Minor)?$")
DISPOSITION_OK = re.compile(r"^(survived|rejected)$")
DECISION_OK = re.compile(r"^(fix-now|fix-later|proceed)$")


def _load_manifest_dedup(mark_path):
    """Load .journaled as a set of local_id keys. Whole-key membership is
    the dedup invariant (test W). On malformed JSONL, fail loud (test R).

    CR-6 (2026-06-09 review): wrap the `open(mark_path, "r")` in
    `try/except (OSError, PermissionError)` so a permission denied / ENOSPC /
    EIO / ENOENT-on-raced surfaces as rc=2 with a named stderr, matching
    the documented fail-loud contract at the file preamble. Without this
    guard, a `.journaled` set to mode 000 crashes with `PermissionError`
    → uncaught traceback → rc=1 (Python default), which violates the
    docstring's "exit 2 on malformed .journaled manifest" guarantee."""
    if not os.path.exists(mark_path):
        return set()
    dedup = set()
    try:
        with open(mark_path, "r", encoding="utf-8") as f:
            for ln, raw in enumerate(f, 1):
                if not raw.strip():
                    continue
                try:
                    obj = json.loads(raw)
                except json.JSONDecodeError:
                    print(
                        f"review-pr-journal: ERROR: {mark_path} line {ln} is not "
                        f"valid JSONL; refusing to retry (a prior run died in a "
                        f"way that left garbage; re-emit would corrupt the journal)",
                        file=sys.stderr,
                    )
                    sys.exit(2)
                lid = obj.get("local_id")
                if lid:
                    dedup.add(lid)
    except (OSError, PermissionError) as e:
        print(
            f"review-pr-journal: ERROR: manifest read failed at {mark_path} "
            f"({type(e).__name__}: {e}); refusing to journal without a "
            f"complete dedup set",
            file=sys.stderr,
        )
        sys.exit(2)
    return dedup


def _build_finding_fields(local_id, file_path, line_num, tier, agent, summary):
    """Compose the review_finding `fields` dict. `line_num` stays None
    (JSON null) for review-body findings (test T). `local_id` is preserved
    in `fields` for human-readability; cross-event linkage uses
    verdict.subject_id, not fields.local_id."""
    return {
        "local_id": local_id,
        "file": file_path,
        "line": line_num,
        "tier": tier,
        "agent": agent,
        "summary": summary,
    }


def _build_verdict_fields(finding_id, disposition, tier, decision, rejected_reason):
    """Compose the verification_verdict `fields` dict. `subject_id` is
    the just-minted finding id (Phase II linkage; Q1=A)."""
    return {
        "subject_id": finding_id,
        "disposition": disposition,
        "tier": tier,
        "decision": decision,
        "rejected_reason": rejected_reason,
    }


def _check_enums(local_id, tier, disposition, decision):
    """Emit WARNINGs on bad enum values (test P). Returns nothing — the
    journal still emits regardless (best-effort contract).

    CR-1 (2026-06-09 review): guard against non-string types BEFORE calling
    re.match — `re.match` raises `TypeError: expected string or bytes-like
    object, got 'int'` on a non-string scalar, which would crash with rc=1
    (Python default) instead of the contracted rc=2. Sister cases:
    `disposition: 7`, `tier: null`, `decision: true`.

    CR-2 (2026-06-09 review): drop the `and` short-circuit on `disposition`
    and `decision` — empty string is falsy, so the validator was bypassed
    for `disposition: ""` and `decision: ""`. `re.match` returns `None` on
    empty string already, so the bypass was net-negative. `tier` keeps the
    short-circuit (empty string is the review-body marker; TIER_OK
    permits it)."""
    if not isinstance(tier, str) or not TIER_OK.match(tier):
        print(
            f"review-pr-journal: WARNING: local_id={local_id} tier={tier!r} "
            f"not in {{Critical,Important,Minor,''}}; emitting anyway",
            file=sys.stderr,
        )
    if not isinstance(disposition, str) or not DISPOSITION_OK.match(disposition):
        print(
            f"review-pr-journal: WARNING: local_id={local_id} disposition={disposition!r} "
            f"not in {{survived,rejected}}; emitting anyway",
            file=sys.stderr,
        )
    if not isinstance(decision, str) or not DECISION_OK.match(decision):
        print(
            f"review-pr-journal: WARNING: local_id={local_id} decision={decision!r} "
            f"not in {{fix-now,fix-later,proceed}}; emitting anyway",
            file=sys.stderr,
        )


def main():
    ap = argparse.ArgumentParser(prog="review-pr-journal", add_help=False)
    ap.add_argument("scratch_dir", help="Path to the /review-pr scratch dir; "
                                         "must contain findings.jsonl")
    args = ap.parse_args()

    sdir = args.scratch_dir
    findings_path = os.path.join(sdir, "findings.jsonl")
    mark_path = os.path.join(sdir, ".journaled")

    # Pre-flight: findings.jsonl must exist AND be a regular file. F3 — a
    # directory at findings.jsonl passed `os.path.exists` then crashed on
    # `open(..., "r")` with IsADirectoryError → uncaught traceback → rc=1
    # (violates the rc=2 contract). `isfile` rejects directories, broken
    # symlinks, FIFOs, devices, all routed to the same exit-2 path.
    if not os.path.isfile(findings_path):
        print(
            f"review-pr-journal: ERROR: missing or not a regular file at "
            f"{findings_path}; cannot journal without findings",
            file=sys.stderr,
        )
        sys.exit(2)

    # SID: set BEFORE calling _lib.journal_append (which reads CLAUDE_SESSION_ID
    # directly, matching the bash path's $SID at review-pr-journal.sh:99).
    # Fallback = the journaler id for self-attribution when $CLAUDE_SESSION_ID
    # is unset (test L's session-fallback assertion).
    os.environ.setdefault("CLAUDE_SESSION_ID", HOOK_ID)

    dedup = _load_manifest_dedup(mark_path)

    n_written = 0
    n_already = 0
    # F4: split `n_skipped` into 3 named counters. The original "non-object
    # line(s) skipped" suffix mis-attributed 3 distinct skip reasons —
    # corrupt JSONL, JSON-non-object (array/scalar), bad local_id — making
    # the summary useless for telling "the input file is corrupt" from
    # "the model emitted findings without a local_id" from "the wrong
    # shape leaked in". Per-line stderr messages preserve the cause;
    # the summary now names the bucket each line landed in.
    n_skip_corrupt = 0
    n_skip_nonobj = 0
    n_skip_badid = 0

    with open(findings_path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                print(
                    f"review-pr-journal: skipping corrupt-JSONL line at offset {n_skip_corrupt}: {line}",
                    file=sys.stderr,
                )
                n_skip_corrupt += 1
                continue
            if not isinstance(obj, dict):
                print(
                    f"review-pr-journal: skipping non-object line at offset {n_skip_nonobj}: {line}",
                    file=sys.stderr,
                )
                n_skip_nonobj += 1
                continue

            local_id = obj.get("local_id") or ""
            # F7: field-validator asymmetry. The original `or ""` collapse
            # on each field silently coerced None, 0, False, [], {}, and any
            # non-string scalar to "" — a finding with `file: 123` (int) was
            # journaled as `file: ""`, which the consumer reads as "no file
            # → no dedup key → TSV twin counted twice". A finding with
            # `line: "abc"` (str when int expected) was journaled as
            # `line: "abc"`, breaking the consumer's "line: null =
            # review-body" rendering. Fail loud on the type, like the
            # local_id validator below.
            #
            # Special cases that must NOT be rejected:
            #   `file: ""` and `tier: ""` are the review-body markers
            #     (per test T and SKILL.md); empty-string is the absence
            #     signal, not a validation error.
            #   `line: null` is the review-body "no file:line" marker
            #     (per test T); None stays None, not coerced to "".
            _raw_file = obj.get("file")
            if _raw_file is not None and not isinstance(_raw_file, str):
                print(
                    f"review-pr-journal: ERROR: finding at offset {n_skip_badid} "
                    f"has non-string `file` field "
                    f"(file={_raw_file!r} type={type(_raw_file).__name__}); "
                    f"skipping emit",
                    file=sys.stderr,
                )
                n_skip_badid += 1
                continue
            file_path = _raw_file or ""
            line_num = obj.get("line")  # None → JSON null (test T) — keep None, do not coerce
            if line_num is not None and (
                not isinstance(line_num, int) or isinstance(line_num, bool)
            ):
                print(
                    f"review-pr-journal: ERROR: finding at offset {n_skip_badid} "
                    f"has non-int `line` field "
                    f"(line={line_num!r} type={type(line_num).__name__}); "
                    f"skipping emit",
                    file=sys.stderr,
                )
                n_skip_badid += 1
                continue
            _raw_summary = obj.get("summary")
            if _raw_summary is not None and not isinstance(_raw_summary, str):
                print(
                    f"review-pr-journal: ERROR: finding at offset {n_skip_badid} "
                    f"has non-string `summary` field "
                    f"(summary={_raw_summary!r} type={type(_raw_summary).__name__}); "
                    f"skipping emit",
                    file=sys.stderr,
                )
                n_skip_badid += 1
                continue
            # CR-3 (2026-06-09 review): F7's `or ""` silent-coercion foot-gun
            # was patched for `file`/`line`/`summary` only. The same
            # silent-drop affected 5 more fields:
            #   - `agent` (free text — reject non-string non-None)
            #   - `tier` (enum, empty allowed for review-body — same rule
            #     as `file`/`line` above: reject non-string non-None)
            #   - `disposition` (enum, empty would be a contract miss — but
            #     CR-2's _check_enums WARNING already covers the empty case;
            #     here we only need to reject non-string non-None)
            #   - `decision` (same shape as disposition)
            #   - `rejected_reason` (free text — reject non-string non-None)
            # A finding with `agent: ["code-reviewer"]` would have journaled
            # `agent: ""` silently. Mirror F7's type-guard pattern.
            _raw_tier = obj.get("tier")
            if _raw_tier is not None and not isinstance(_raw_tier, str):
                print(
                    f"review-pr-journal: ERROR: finding at offset {n_skip_badid} "
                    f"has non-string `tier` field "
                    f"(tier={_raw_tier!r} type={type(_raw_tier).__name__}); "
                    f"skipping emit",
                    file=sys.stderr,
                )
                n_skip_badid += 1
                continue
            _raw_agent = obj.get("agent")
            if _raw_agent is not None and not isinstance(_raw_agent, str):
                print(
                    f"review-pr-journal: ERROR: finding at offset {n_skip_badid} "
                    f"has non-string `agent` field "
                    f"(agent={_raw_agent!r} type={type(_raw_agent).__name__}); "
                    f"skipping emit",
                    file=sys.stderr,
                )
                n_skip_badid += 1
                continue
            _raw_disposition = obj.get("disposition")
            if _raw_disposition is not None and not isinstance(_raw_disposition, str):
                print(
                    f"review-pr-journal: ERROR: finding at offset {n_skip_badid} "
                    f"has non-string `disposition` field "
                    f"(disposition={_raw_disposition!r} "
                    f"type={type(_raw_disposition).__name__}); skipping emit",
                    file=sys.stderr,
                )
                n_skip_badid += 1
                continue
            _raw_decision = obj.get("decision")
            if _raw_decision is not None and not isinstance(_raw_decision, str):
                print(
                    f"review-pr-journal: ERROR: finding at offset {n_skip_badid} "
                    f"has non-string `decision` field "
                    f"(decision={_raw_decision!r} type={type(_raw_decision).__name__}); "
                    f"skipping emit",
                    file=sys.stderr,
                )
                n_skip_badid += 1
                continue
            _raw_rejected_reason = obj.get("rejected_reason")
            if _raw_rejected_reason is not None and not isinstance(_raw_rejected_reason, str):
                print(
                    f"review-pr-journal: ERROR: finding at offset {n_skip_badid} "
                    f"has non-string `rejected_reason` field "
                    f"(rejected_reason={_raw_rejected_reason!r} "
                    f"type={type(_raw_rejected_reason).__name__}); skipping emit",
                    file=sys.stderr,
                )
                n_skip_badid += 1
                continue
            tier = _raw_tier or ""
            agent = _raw_agent or ""
            summary = _raw_summary or ""
            disposition = _raw_disposition or ""
            decision = _raw_decision or ""
            rejected_reason = _raw_rejected_reason or ""

            # local_id validator — fail loud, skip the emit (test X). An
            # empty or non-string local_id would silently collapse under the
            # same dedup key (`in dedup` does str/str hashing for the manifest
            # path, but a non-str scalar would hash differently and bypass
            # dedup on re-run). Require `isinstance(..., str)` to make the
            # contract honest.
            if not isinstance(local_id, str) or not local_id:
                print(
                    f"review-pr-journal: ERROR: finding at offset {n_skip_badid} "
                    f"has non-string or empty local_id "
                    f"(local_id={local_id!r} type={type(local_id).__name__} "
                    f"file='{file_path}' line='{line_num}'); skipping emit",
                    file=sys.stderr,
                )
                n_skip_badid += 1
                continue

            # Partial-run recovery: skip if this local_id is already in the
            # manifest (test N, N2). Whole-key set membership preserves
            # multi-line / adversarial local_ids as one record (test U, W).
            if local_id in dedup:
                print(
                    f"review-pr-journal: local_id={local_id} already journaled; skipping",
                    file=sys.stderr,
                )
                n_already += 1
                continue

            _check_enums(local_id, tier, disposition, decision)

            # Emit the finding; capture the minted id for the verdict's
            # subject_id (Phase II linkage).
            finding_fields = _build_finding_fields(
                local_id, file_path, line_num, tier, agent, summary
            )
            finding_id = _lib.journal_append(HOOK_ID, "review_finding", finding_fields)

            # Emit the verdict, also capturing the id for the manifest
            # (test V: journal finding_id/verdict_id match manifest).
            verdict_fields = _build_verdict_fields(
                finding_id, disposition, tier, decision, rejected_reason
            )
            verdict_id = _lib.journal_append(
                HOOK_ID, "verification_verdict", verdict_fields
            )

            # Manifest append — atomic per-line write (test V linkage). The
            # bash version used `jq -nc` for JSON-escaping; json.dumps with
            # compact separators matches the byte shape of the prior
            # manifest (test U round-trips adversarial local_ids cleanly).
            #
            # CR-5 (2026-06-09 review): wrap the manifest open() in
            # `try/except OSError` so a partial-run crash (ENOSPC / EROFS /
            # EINTR / OOM) doesn't leave the journal line written but the
            # manifest NOT updated — that would silently break the dedup
            # invariant and re-emit duplicates on the next run. The journal
            # emit above may have already succeeded (so 2 events are on
            # disk); the operator needs to know which ids to manually append
            # to the dedup set. Exit 2 per the docstring contract.
            try:
                with open(mark_path, "a", encoding="utf-8") as mf:
                    mf.write(
                        json.dumps(
                            {
                                "local_id": local_id,
                                "finding_id": finding_id,
                                "verdict_id": verdict_id,
                            },
                            ensure_ascii=False,
                            separators=(",", ":"),
                        )
                        + "\n"
                    )
            except OSError as e:
                print(
                    f"review-pr-journal: ERROR: manifest write failed at "
                    f"{mark_path} ({type(e).__name__}: {e}); journaled ids = "
                    f"{finding_id}, {verdict_id} — manually append to dedup "
                    f"set or the next run will re-emit duplicates",
                    file=sys.stderr,
                )
                sys.exit(2)

            dedup.add(local_id)  # in-memory dedup for repeated local_ids in the same run
            n_written += 1

    # Counter summary — same shape as review-pr-journal.sh:231 so downstream
    # log-greppers (and the audit test) find the same fields. F4: each
    # skip bucket is named so the operator can tell which kind of input
    # defect they're seeing.
    n_skipped_total = n_skip_corrupt + n_skip_nonobj + n_skip_badid
    print(
        f"review-pr-journal: {n_written} pair(s) written, {n_already} already journaled, "
        f"{n_skipped_total} skipped "
        f"(corrupt={n_skip_corrupt} non-object={n_skip_nonobj} bad-local_id={n_skip_badid}); "
        f"manifest={mark_path}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
