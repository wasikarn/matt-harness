# 30. Eval-target freshness — every `**/evals.json` and the baseline-eval
# driver carries a `last_reviewed:` (ISO date) field. If the date is older
# than KBG_EVAL_MAX_AGE_DAYS (default 180) AND there's no sibling
# `last_reviewed_reason:` justifying the staleness, emit info. This catches
# the "evals were great 6 months ago, has the skill drifted?" case the
# per-fix gate-rot check can't see — gate-rot is per-fix, this is per-target.
# Default of 180d matches decay-cadence quarter; tune via env var.
# 2026-06-11: added in response to the Harness-Loop-Engineer audit FIX-2.
KBG_EVAL_MAX_AGE_DAYS="${KBG_EVAL_MAX_AGE_DAYS:-180}"
if command -v python3 >/dev/null 2>&1; then
  # Collect candidate files. We pass paths via NUL delimiters so a path with
  # spaces (rare in this repo, but cheap to handle) doesn't get mangled.
  EVAL_TARGETS=()
  while IFS= read -r -d '' f; do EVAL_TARGETS+=("$f"); done < <(find "$REPO_ROOT/tests/evals/skills" -type f -name 'evals.json' -print0 2>/dev/null || true)
  while IFS= read -r -d '' f; do EVAL_TARGETS+=("$f"); done < <(find "$REPO_ROOT/scripts" -maxdepth 2 -type f -name 'run-baseline-eval.py' -print0 2>/dev/null || true)
  if [ "${#EVAL_TARGETS[@]}" -gt 0 ]; then
    while IFS=$'\t' read -r eval_path age_days has_reason reason_text; do
      [ -n "$eval_path" ] || continue
      rel="${eval_path#"$REPO_ROOT"/}"
      if [ "$age_days" = "missing" ]; then
        # No last_reviewed field at all. The whole point of this check is
        # to surface files that haven't been touched — but a documented
        # `last_reviewed_reason:` (per the convention introduced in
        # 2026-06-11 to defer until a human gets to a real review) IS
        # a touch: the file was opened, the deferral was a deliberate
        # decision, and the quarterly cadence owns the rotation. Honor it
        # the same way the stale branch does.
        if [ "$has_reason" != "1" ]; then
          info "eval-target freshness: $rel missing 'last_reviewed:' field — add one (YYYY-MM-DD)"
        fi
      elif [ "$age_days" -gt "$KBG_EVAL_MAX_AGE_DAYS" ] 2>/dev/null && [ "$has_reason" != "1" ]; then
        info "eval-target freshness: $rel last reviewed $age_days days ago — revisit (or add last_reviewed_reason: to defer)"
      fi
    done < <(KBG_EVAL_MAX_AGE_DAYS="$KBG_EVAL_MAX_AGE_DAYS" python3 - "${EVAL_TARGETS[@]}" <<'PY' 2>/dev/null
import datetime as dt, json, os, re, sys
targets = sys.argv[1:]
max_age = int(os.environ.get("KBG_EVAL_MAX_AGE_DAYS", "180"))
today = dt.date.today()
# .py header: scan first 50 lines for a `last_reviewed: YYYY-MM-DD` line.
# evals.json: scan the first ~3KB for the same field (kept loose since
# people put it in different positions — sibling `last_reviewed_reason:`
# counts as a documented justification for staleness).
LINE_RE = re.compile(r"^[\s#/*-]*last_reviewed:\s*(\d{4}-\d{2}-\d{2})", re.MULTILINE)
# Allow JSON key form ("last_reviewed_reason": …) in addition to YAML and
# comment form. The leading char class is greedy by design — the literal
# 'last_reviewed_reason' token after it pins the match to the right key
# (so 'blast_reviewed_reason' / 'skill_name' do not match).
REASON_RE = re.compile(r"""^[\s#/*'"]*last_reviewed_reason["']?\s*:\s*\S+""", re.MULTILINE)
for path in targets:
    try:
        text = open(path, encoding="utf-8", errors="replace").read(8192)
    except OSError:
        continue
    m = LINE_RE.search(text)
    if not m:
        # Try JSON parse to catch "last_reviewed" as a key (camelCase OK).
        try:
            data = json.loads(open(path, encoding="utf-8", errors="replace").read())
            if isinstance(data, dict):
                v = data.get("last_reviewed") or data.get("lastReviewed")
                if v:
                    try: dt.date.fromisoformat(str(v))
                    except ValueError: pass
                    else:
                        # JSON path: look for reason at the same level
                        reason = data.get("last_reviewed_reason") or data.get("lastReviewedReason")
                        if reason:
                            print(f"{path}\t{(today - dt.date.fromisoformat(str(v))).days}\t1\t{reason}")
                            continue
                        print(f"{path}\t{(today - dt.date.fromisoformat(str(v))).days}\t0\t")
                        continue
                # No `last_reviewed` AND no `last_reviewed:` line — but the
                # file may still carry a `last_reviewed_reason:` in the JSON
                # (the convention introduced to defer stamping until a
                # human gets to a real review). The same justification that
                # suppresses the stale branch should suppress the missing
                # branch, so we don't surface noise for deliberately-deferred
                # targets.
                reason_only = data.get("last_reviewed_reason") or data.get("lastReviewedReason")
                if reason_only:
                    print(f"{path}\tmissing\t1\t{reason_only}")
                    continue
        except (OSError, ValueError):
            pass
        print(f"{path}\tmissing\t0\t")
        continue
    try:
        d = dt.date.fromisoformat(m.group(1))
    except ValueError:
        # Line matched `last_reviewed:` but the date was unparseable.
        # Treat as missing — and check for a `last_reviewed_reason:`
        # justification before flagging (same convention as the JSON branch).
        if REASON_RE.search(text):
            reason_text = REASON_RE.search(text).group(0)
            print(f"{path}\tmissing\t1\t{reason_text}")
        else:
            print(f"{path}\tmissing\t0\t")
        continue
    has_reason = "1" if REASON_RE.search(text) else "0"
    age = (today - d).days
    reason_text = REASON_RE.search(text).group(0) if has_reason == "1" else ""
    print(f"{path}\t{age}\t{has_reason}\t{reason_text}")
PY
)
  fi
else
  warn "eval-target freshness check skipped — python3 unavailable"
fi

