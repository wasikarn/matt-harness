#!/bin/bash
# learn-capture.sh — SessionEnd advisory sensor (computational-FB).
#
# Passively harvests durable, reusable learnings (operator corrections, stated
# preferences) from the session transcript and APPENDS them as JSONL candidate
# rows to the out-of-repo queue. It is the capture half of the ECC continuous-
# learning idea, with the apply half kept HUMAN-GATED (kbg:learn). It NEVER
# mutates the repo, NEVER emits a permissionDecision, and ALWAYS exits 0.
# Governance: docs/adr/0002-addendum-passive-capture.md. Contract: the schema at
# skills/learn/CANDIDATE-SCHEMA.md (queue path, row shape, secret-scrub).
#
# Default-ON: disable with `export KBG_LEARN_CAPTURE=0` (opt-out).
# Bypass: export CLAUDE_DISABLED_HOOKS=learn-capture
#
# Failure mode: silent. Always exit 0; never block SessionEnd.

HOOK_ID="learn-capture"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

# Default-ON gate; opt out with KBG_LEARN_CAPTURE=0 (ADR 0002 addendum). Capture is
# advisory (out-of-repo queue, secret-scrubbed, never gates) so on-by-default is within
# the addendum's "capture is automatic" envelope — APPLY stays human-gated in kbg:learn.
[ "${KBG_LEARN_CAPTURE:-1}" = "0" ] && exit 0

# Hard deps: degrade to a silent no-op if absent (no bundled deps).
command -v jq      >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID_VAL=$(printf '%s\n' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SESSION_ID_VAL" ] || SESSION_ID_VAL="no-sid"

# No readable transcript = nothing to harvest (normal for very short sessions).
{ [ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ]; } && exit 0

# Transcript-size budget guard: bound the python walk. Skip pathological logs.
TSIZE=$(wc -c < "$TRANSCRIPT" 2>/dev/null || echo 0)
[ "${TSIZE:-0}" -gt 2097152 ] 2>/dev/null && exit 0

# Queue dir derives from the transcript's OWN parent dir (CANDIDATE-SCHEMA.md
# "Queue location" — the slug CC chose, so writer + reader always agree).
PROJECT_MEM_DIR="$(dirname "$TRANSCRIPT")/memory"
CAND_DIR="$PROJECT_MEM_DIR/_candidates"
QUEUE="$CAND_DIR/queue.jsonl"
PROJECT_SLUG="$(basename "$(dirname "$TRANSCRIPT")")"
# mkdir || exit 0 (first-run must not fail; copy of ideate-budget-capture.sh:21).
mkdir -p "$CAND_DIR" || exit 0

# Single python pass: role==user turns only, word-boundary correction/preference
# shapes, secret-scrub with whole-row drop, dedup within session, APPEND rows.
RESULT=$(
  KBG_LC_TRANSCRIPT="$TRANSCRIPT" \
  KBG_LC_QUEUE="$QUEUE" \
  KBG_LC_SID="$SESSION_ID_VAL" \
  KBG_LC_SLUG="$PROJECT_SLUG" \
  python3 - <<'PY' 2>/dev/null
import json, os, re, datetime as dt
from pathlib import Path

T = os.environ["KBG_LC_TRANSCRIPT"]
QUEUE = os.environ["KBG_LC_QUEUE"]
SID = os.environ.get("KBG_LC_SID", "no-sid")
SLUG = os.environ.get("KBG_LC_SLUG", "")
TODAY = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
TS = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# --- precision-tight harvest patterns (require correction/preference STRUCTURE,
# not a bare "no"). Applied to quote/tag-stripped genuine user text only. ---
CORRECTION = re.compile(
    r"(?i)("
    r"\bno,?\s+(?:use|do|don't|do not|not|let's|it's|that's)\b"
    r"|\buse\s+\S+\s+not\s+\S+"
    r"|\bnot\s+\S+\s*,?\s*use\b"
    r"|\binstead\s+of\b"
    r"|\bdon't\s+\S+\s*,?\s+(?:use|do)\b"
    r"|\bthat(?:'s| is)\s+(?:wrong|incorrect|not right|not correct)\b"
    r"|\bshould\s+be\s+\S+\s+not\b"
    r"|\brather\s+than\b"
    r")"
)
PREFERENCE = re.compile(
    r"(?i)("
    r"\balways\s+(?!thought\b|wondered\b|felt\b|figured\b|assumed\b|wanted\b|knew\b|liked\b)\S+"
    r"|\bnever\s+(?!mind\b|thought\b|seen\b|heard\b|been\b|going\b|gonna\b|really\b|knew\b|liked\b)\S+"
    r"|\bin this repo we\b"
    r"|\bi prefer\b"
    r"|\bfrom now on\b"
    r"|\bplease\s+(?:always|never)\b"
    r")"
)

# secret-scrub deny-list (mirror _lib.sh val_dl). Any match => DROP whole row.
SECRET = re.compile(
    r"(?i)(password|api_key|secret|token|credential"
    r"|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}"
    r"|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN[A-Z ]*PRIVATE KEY"
    r"|[a-z][a-z0-9+.-]*://[^/@\s]+:[^/@\s]+@)"
)

# strip backtick code spans, fenced blocks, and injected harness tags so a "no"
# inside a code comment / <system-reminder> / local-command block is not matched.
TAG = re.compile(r"<(system-reminder|local-command[^>]*|command-name|command-args|persisted-output)>.*?</\1>", re.S)
SELFCLOSE = re.compile(r"<[^>]+/>")
# ponytail: backtick kept as \x60 (not literal) so bash 3.2's parser doesn't
# misread it inside this <<'PY' heredoc — bash 3.2 -n hunts literal backticks in
# quoted-heredoc bodies and false-positives "unexpected EOF"; 5.x is unaffected.
# Byte-identical to the old r"```.*?```" / r"`[^`]*`" forms.
BT = "\x60"
FENCE = re.compile(BT * 3 + ".*?" + BT * 3, re.S)
BACKTICK = re.compile(BT + "[^" + BT + "]*" + BT)


def clean(text):
    text = TAG.sub(" ", text)
    text = FENCE.sub(" ", text)
    text = BACKTICK.sub(" ", text)
    text = SELFCLOSE.sub(" ", text)
    return text


def extract_text(content):
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                # genuine typed text only — tool_result/tool_use blocks are skipped
                if item.get("type") == "text":
                    parts.append(item.get("text", ""))
            elif isinstance(item, str):
                parts.append(item)
        return "\n".join(parts)
    return ""


def is_user_turn(obj):
    if not isinstance(obj, dict):
        return False
    if obj.get("type") != "user":
        return False
    msg = obj.get("message")
    if isinstance(msg, dict):
        if msg.get("role") not in (None, "user"):
            return False
        content = msg.get("content")
    else:
        content = obj.get("content")
    # tool_result turns are type==user but content is a tool_result list — reject
    if isinstance(content, list):
        for it in content:
            if isinstance(it, dict) and it.get("type") == "tool_result":
                return False
    return True


def user_text(obj):
    msg = obj.get("message")
    content = msg.get("content") if isinstance(msg, dict) else obj.get("content")
    return extract_text(content)


p = Path(T)
try:
    raw = p.read_text(encoding="utf-8", errors="replace")
except OSError:
    print("0 0")
    raise SystemExit(0)

seen = set()  # dedup within session by (kind, normalized evidence)
rows = []
kinds = {"correction": 0, "preference": 0}

for line in raw.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue
    if not is_user_turn(obj):
        continue
    text = clean(user_text(obj)).strip()
    if not text or len(text) > 4000:
        continue

    for kind, rx in (("correction", CORRECTION), ("preference", PREFERENCE)):
        m = rx.search(text)
        if not m:
            continue
        trigger = m.group(0).strip()
        # evidence = the sentence/window around the match, capped at 280 chars
        start = max(0, m.start() - 80)
        evidence = " ".join(text[start:m.end() + 200].split())[:280]
        # secret-scrub: ANY match in trigger OR evidence => drop the whole row
        if SECRET.search(trigger) or SECRET.search(evidence):
            continue
        key = (kind, re.sub(r"\s+", " ", evidence.lower()))
        if key in seen:
            continue
        seen.add(key)
        kinds[kind] += 1
        rows.append({
            "ts": TS,
            "session_id": SID,
            "project_slug": SLUG,
            "kind": kind,
            "trigger": trigger,
            "evidence": evidence,
            "seen_count": 1,
            "first_seen": TODAY,
            "last_seen": TODAY,
            "scope": "repo",
            "source": "learn-capture",
            "status": "open",
        })

if rows:
    # append-only (no cap/rotate here — kill-safe; read-candidates.sh owns rotate)
    with open(QUEUE, "a", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, separators=(",", ":")) + "\n")

# emit: <queued> <queue_total>  (kinds via stderr-free stdout second line)
total = 0
try:
    with open(QUEUE, encoding="utf-8") as f:
        total = sum(1 for ln in f if ln.strip())
except OSError:
    total = len(rows)
print(f"{len(rows)} {total} {kinds['correction']} {kinds['preference']}")
PY
)

# Parse the python output: "<queued> <total> <corrections> <preferences>".
read -r QUEUED QUEUE_TOTAL N_CORR N_PREF <<<"${RESULT:-0 0 0 0}"
[ -n "$QUEUED" ] || QUEUED=0
[ "$QUEUED" -gt 0 ] 2>/dev/null || exit 0

# Journal counts only (no secret-named fields — JOURNAL-SCHEMA.md redactor rule).
# Best-effort: a journaling failure must not change the exit code.
( journal_append "$HOOK_ID" "learning_candidates" \
    "$(jq -nc --argjson q "$QUEUED" --argjson c "${N_CORR:-0}" --argjson p "${N_PREF:-0}" --argjson t "${QUEUE_TOTAL:-0}" \
       '{queued:$q, corrections:$c, preferences:$p, queue_total:$t}')" \
    >/dev/null 2>&1 ) || true

exit 0
