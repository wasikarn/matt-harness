#!/usr/bin/env python3
"""
Post-edit async security-diff review — layer-2 heuristic scan after Edit/Write.
Fires async so it doesn't block the user's next turn.

Checks additions (+ lines in git diff) for security-sensitive patterns:
  - SQL injection (string interpolation in SQL)
  - Command injection (eval, exec, system, child_process.exec, backticks)
  - XSS vectors (innerHTML, dangerouslySetInnerHTML, document.write)
  - Path traversal (unsanitized user input in fs paths)
  - Unsafe deserialization (pickle.loads, yaml.load without Loader, eval)
  - Hardcoded secrets (API keys, tokens, passwords in added lines)
  - SSRF / unchecked outbound URLs (fetch with user-controlled URL)
  - Missing auth on new endpoints (route definitions without middleware)

Log:    $HOME/.claude/security-diff-review.log    (human-readable TSV)
Events: $HOME/.claude/governance-events.jsonl     (structured audit stream;
        shared schema other governance hooks may append to)
Bypass: CLAUDE_DISABLED_HOOKS=security-diff-review
"""

import json
import os
import re
import subprocess
import sys
import uuid
from datetime import datetime, timezone

HOOK_ID = "security-diff-review"
DISABLED = os.environ.get("CLAUDE_DISABLED_HOOKS", "")
LOG = os.path.join(os.path.expanduser("~"), ".claude", "security-diff-review.log")
# Structured governance audit stream (concept ported from affaan-m/ECC
# governance-capture, 2026-05-30). One JSONL event per finding — machine-readable
# and severity-tagged for triage, unlike the human-readable TSV LOG above. The
# schema is deliberately generic so other governance hooks can append events of
# the same shape to one shared stream.
EVENTS = os.path.join(os.path.expanduser("~"), ".claude", "governance-events.jsonl")

# Heuristic category -> severity for the audit stream (triage only, not a gate).
SEVERITY = {
    "HARDCODED_SECRET": "critical",
    "SQL_INJECTION": "high",
    "COMMAND_INJECTION": "high",
    "UNSAFE_DESER": "high",
    "SSRF": "high",
    "XXE": "high",
    "XSS": "medium",
    "PATH_TRAVERSAL": "medium",
    "MISSING_AUTH": "medium",
    "WEAK_CRYPTO": "medium",
}


def _now_ms():
    """Millisecond epoch — composes the journal `id`. Contract-equivalent to the
    bash `_now_ms` in _lib.sh (same value; the envelope is language-agnostic)."""
    return int(datetime.now(timezone.utc).timestamp() * 1000)


# Deny-list backstop so this python producer honors the redaction invariant the
# bash journal_append does (JOURNAL-SCHEMA.md), closing the producer asymmetry.
# Difference from _lib.sh by design: this hook's VALUES are controlled generic
# text — a finding detail legitimately reads "possible hardcoded credential…",
# so word-matching values would be pure false-positive. So values match secret
# SHAPES only (a real embedded AKIA…/ghp_…/PEM key), while keys still match the
# word list (harmless — this hook's keys never do). Today `detail` carries no
# matched secret text, so this is defense-in-depth against a future change.
_REDACT_KEY = re.compile(r"password|api_key|secret|token|credential", re.I)
_REDACT_VAL = re.compile(
    r"AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|"
    r"xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN[A-Z ]*PRIVATE KEY|"
    r"[a-z][a-z0-9+.\-]*://[^/@\s]+:[^/@\s]+@",
    re.I,
)


def _redact(value, key=None):
    """Redact a value whose KEY or string content matches a secret name/shape.
    Recurses dict + list, same surface as the _lib.sh jq walk."""
    if key is not None and _REDACT_KEY.search(key):
        return "[redacted]"
    if isinstance(value, dict):
        return {k: _redact(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [_redact(v) for v in value]
    if isinstance(value, str) and _REDACT_VAL.search(value):
        return "[redacted]"
    return value


def main():
    if HOOK_ID in DISABLED.split(","):
        return

    raw = sys.stdin.read()
    if not raw:
        return

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return

    file_path = (
        payload.get("tool_input", {}).get("file_path")
        or payload.get("tool_input", {}).get("path")
        or ""
    )
    if not file_path:
        return

    # Skip non-code files
    CODE_EXTS = (
        ".py", ".js", ".ts", ".jsx", ".tsx", ".go", ".rb", ".java",
        ".kt", ".swift", ".rs", ".php", ".c", ".cpp", ".h",
        ".scala", ".clj", ".elm", ".elm", ".vue", ".svelte",
    )
    if not file_path.endswith(CODE_EXTS):
        return

    # Determine diff source: tracked file vs untracked
    try:
        subprocess.run(
            ["git", "ls-files", "--error-unmatch", file_path],
            capture_output=True,
            check=True,
            cwd=os.path.dirname(file_path) or ".",
        )
        # Tracked — diff against HEAD
        diff_proc = subprocess.run(
            ["git", "diff", "HEAD", "--", file_path],
            capture_output=True,
            text=True,
            cwd=os.path.dirname(file_path) or ".",
        )
        diff = diff_proc.stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Untracked or not in git — read whole file as "diff"
        try:
            with open(file_path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            diff = "\n".join(f"+{line}" for line in content.splitlines())
        except OSError:
            return

    if not diff:
        return

    findings = scan_diff(diff, file_path)
    if not findings:
        return

    now = datetime.now(timezone.utc)
    ts = now.strftime("%Y-%m-%dT%H:%M:%S")                      # TSV (format unchanged)
    ev_ts = now.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"     # JSONL envelope (ms, aware)
    session_id = payload.get("session_id", "unknown")

    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as log:
        for finding in findings:
            log.write(f"{ts}\t{session_id}\t{file_path}\t{finding}\n")

    # Structured governance event stream — one nested-envelope event per finding.
    # Matches claude/hooks/JOURNAL-SCHEMA.md; source=legacy_security_hook marks
    # this as the python producer migrated from the old flat shape (B1 / audit #6).
    with open(EVENTS, "a", encoding="utf-8") as events:
        for finding in findings:
            category, _, detail = finding.partition(":")
            category = category.strip()
            events.write(json.dumps({
                "id": f"{_now_ms()}-{HOOK_ID}-{uuid.uuid4().hex[:8]}",
                "ts": ev_ts,
                "session": session_id,
                "hook": HOOK_ID,
                "event": "security_finding",
                "source": "legacy_security_hook",
                "fields": _redact({
                    "file": file_path,
                    "category": category,
                    "severity": SEVERITY.get(category, "medium"),
                    "detail": detail.strip(),
                }),
            }, ensure_ascii=False) + "\n")

    # Non-blocking advisory notification
    print(f"\033]9;security-diff-review: {len(findings)} finding(s) in {file_path}\007", file=sys.stderr)


def scan_diff(diff: str, file_path: str) -> list:
    findings = []
    added_lines = []
    for line in diff.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            added_lines.append(line[1:])
    if not added_lines:
        return findings

    text = "\n".join(added_lines)
    lower = text.lower()
    ext = os.path.splitext(file_path)[1].lower()

    # 1. SQL injection
    sql_patterns = [
        r"SELECT\s+.*\+\s*",
        r"INSERT\s+INTO\s+.*\+\s*",
        r"UPDATE\s+.*SET\s+.*\+\s*",
        r"DELETE\s+FROM\s+.*\+\s*",
        r"\.format\s*\(.*['\"]\s*SELECT",
        r"f['\"].*SELECT\s+.*\{.*\}",
        r"f['\"].*INSERT\s+.*\{.*\}",
        r"f['\"].*UPDATE\s+.*\{.*\}",
        r"\$\{.*\}.*SELECT",
        r"\$\{.*\}.*INSERT",
        r"\$\{.*\}.*UPDATE",
        r"\$\{.*\}.*DELETE",
        r"query\s*\(\s*[`\"'].*\$\{",
        r"query\s*\(\s*f['\"]",
        r"query\s*\(\s*.*\+\s*",
        r"execute\s*\(\s*[`\"'].*\$\{",
        r"execute\s*\(\s*f['\"]",
        r"execute\s*\(\s*.*\+\s*",
        r"raw\s*\(\s*[`\"'].*\$\{",
        r"raw\s*\(\s*f['\"]",
        r"raw\s*\(\s*.*\+\s*",
    ]
    for pat in sql_patterns:
        if re.search(pat, text, re.IGNORECASE):
            findings.append("SQL_INJECTION: possible string interpolation in SQL query")
            break

    # 2. Command injection
    cmd_patterns = [
        r"eval\s*\(",
        r"exec\s*\(",
        r"os\.system\s*\(",
        r"subprocess\.call\s*\(",
        r"subprocess\.run\s*\([^)]*shell\s*=\s*True",
        r"child_process\.exec\s*\(",
        r"child_process\.execSync\s*\(",
        r"[`\"'].*\$\{.*\}.*[`\"']",  # template literal with interpolation passed to shell
        r"\bspawn\s*\(",
        r"\bpopen\s*\(",
        r"shell_exec\s*\(",
        r"passthru\s*\(",
        r"backticks\s*\(",
        r"\bnew\s+Function\s*\(",
    ]
    for pat in cmd_patterns:
        if re.search(pat, text, re.IGNORECASE):
            findings.append("COMMAND_INJECTION: possible command execution with dynamic input")
            break

    # 3. XSS
    xss_patterns = [
        r"\.innerHTML\s*=",
        r"\.outerHTML\s*=",
        r"\.insertAdjacentHTML\s*\(",
        r"dangerouslySetInnerHTML",
        r"document\.write\s*\(",
        r"\bhtml\s*=\s*.*\$\{",
        r"v-html\s*=",
    ]
    for pat in xss_patterns:
        if re.search(pat, text, re.IGNORECASE):
            findings.append("XSS: possible raw HTML injection")
            break

    # 4. Path traversal
    path_patterns = [
        r"open\s*\(\s*.*\+\s*",
        r"readFile\s*\(\s*.*\+\s*",
        r"writeFile\s*\(\s*.*\+\s*",
        r"send_file\s*\(",
        r"sendfile\s*\(",
        r"res\.sendFile\s*\(",
        r"fs\.readFileSync\s*\(\s*.*\$\{",
        r"fs\.writeFileSync\s*\(\s*.*\$\{",
        r"path\.join\s*\([^)]*req\.",
        r"path\.join\s*\([^)]*request\.",
        r"path\.join\s*\([^)]*params\.",
        r"\.join\s*\([^)]*\+\s*",
    ]
    for pat in path_patterns:
        if re.search(pat, text, re.IGNORECASE):
            findings.append("PATH_TRAVERSAL: possible unsanitized path construction")
            break

    # 5. Unsafe deserialization
    deser_patterns = [
        r"pickle\.loads?\s*\(",
        r"yaml\.load\s*\([^)]*\)(?!.*Loader)",
        r"yaml\.load\s*\([^)]*\)(?!.*SafeLoader)",
        r"yaml\.unsafe_load\s*\(",
        r"json\.loads?\s*\([^)]*\)(?!.*schema)",
        r"unserialize\s*\(",
        r"ObjectInputStream",
        r"\.readObject\s*\(",
        # curated dangerous loaders (mined from upstream security-guidance patterns.py)
        r"\bmarshal\.loads?\s*\(",
        r"\bshelve\.open\s*\(",
        r"\b(cPickle|cloudpickle|dill)\.loads?\s*\(",
        r"\bjoblib\.load\s*\(",
        r"\b(pd|pandas)\.read_pickle\s*\(",
        r"\b(np|numpy)\.load\s*\([^)\n]{0,200}allow_pickle\s*=\s*True",
        r"\btorch\.load\s*\((?![^)\n]{0,200}weights_only\s*=\s*True)",
    ]
    for pat in deser_patterns:
        if re.search(pat, text, re.IGNORECASE):
            findings.append("UNSAFE_DESER: possible unsafe deserialization without validation")
            break

    # 6. Hardcoded secrets
    secret_patterns = [
        r"api[_-]?key\s*[=:]\s*['\"][a-zA-Z0-9_\-]{16,}['\"]",
        r"api[_-]?secret\s*[=:]\s*['\"][a-zA-Z0-9_\-]{16,}['\"]",
        r"token\s*[=:]\s*['\"][a-zA-Z0-9_\-\.]{20,}['\"]",
        r"password\s*[=:]\s*['\"][^'\"]{8,}['\"]",
        r"secret\s*[=:]\s*['\"][a-zA-Z0-9_\-]{16,}['\"]",
        r"auth[_-]?token\s*[=:]\s*['\"][a-zA-Z0-9_\-\.]{20,}['\"]",
        r"bearer\s+[a-zA-Z0-9_\-\.]{20,}",
        r"sk-[a-zA-Z0-9]{20,}",
        r"AKIA[0-9A-Z]{16}",
        r"ghp_[a-zA-Z0-9]{36,}",
        r"glpat-[a-zA-Z0-9_\-]{20,}",
    ]
    for pat in secret_patterns:
        if re.search(pat, text, re.IGNORECASE):
            findings.append("HARDCODED_SECRET: possible hardcoded credential in added code")
            break

    # 7. SSRF / unchecked outbound URLs
    ssrf_patterns = [
        r"fetch\s*\(\s*.*\$\{",
        r"fetch\s*\(\s*.*\+\s*",
        r"axios\.[a-z]+\s*\(\s*.*\$\{",
        r"axios\.[a-z]+\s*\(\s*.*\+\s*",
        r"requests\.[a-z]+\s*\(\s*.*\+\s*",
        r"requests\.[a-z]+\s*\(\s*.*\$\{",
        r"http\.get\s*\(\s*.*\$\{",
        r"http\.get\s*\(\s*.*\+\s*",
        r"curl\s+.*\$",
        r"urllib\.request\.urlopen\s*\(\s*.*\+\s*",
        r"urllib\.request\.urlopen\s*\(\s*.*\$\{",
    ]
    for pat in ssrf_patterns:
        if re.search(pat, text, re.IGNORECASE):
            findings.append("SSRF: possible unchecked user-controlled URL in outbound request")
            break

    # 8. Missing auth on new endpoints
    if ext in (".js", ".ts", ".jsx", ".tsx", ".py", ".go", ".rb", ".php"):
        route_patterns = [
            r"\.(get|post|put|patch|delete)\s*\(\s*['\"]",
            r"@app\.(route|get|post|put|patch|delete)\s*\(",
            r"router\.(get|post|put|patch|delete)\s*\(",
            r"\bhandlefunc\s*\(",
            r"mux\.HandleFunc\s*\(",
        ]
        has_route = any(re.search(pat, text, re.IGNORECASE) for pat in route_patterns)
        has_auth = re.search(r"auth|middleware|guard|protect|require_auth|authenticate", lower)
        if has_route and not has_auth:
            findings.append("MISSING_AUTH: new endpoint definition without visible auth check — verify manually")

    # 9. Weak cryptography / disabled TLS verification (mined from upstream security-guidance)
    crypto_patterns = [
        r"\bcrypto\.(createCipher|createDecipher)\b",
        r"\bAES\.MODE_ECB\b",
        r"\bmodes\.ECB\s*\(",
        r"['\"]aes-\d+-ecb['\"]",
        r"\bverify\s*=\s*False\b",
        r"rejectUnauthorized\s*:\s*false",
        r"InsecureSkipVerify\s*:\s*true",
        r"NODE_TLS_REJECT_UNAUTHORIZED\s*=\s*['\"]?0",
        r"ssl\._create_unverified_context",
        r"check_hostname\s*=\s*False",
    ]
    for pat in crypto_patterns:
        if re.search(pat, text, re.IGNORECASE):
            findings.append("WEAK_CRYPTO: insecure cipher mode, legacy cipher API, or disabled TLS verification")
            break

    # 10. XXE — unsafe XML parsing (mined from upstream security-guidance)
    xxe_patterns = [
        r"\b(xml\.etree\.ElementTree|ElementTree|ET)\.(parse|fromstring|XML)\s*\(",
        r"\bminidom\.(parse|parseString)\s*\(",
        r"\bxml\.sax\.(parse|make_parser)\b",
    ]
    for pat in xxe_patterns:
        if re.search(pat, text, re.IGNORECASE):
            findings.append("XXE: stdlib XML parser vulnerable to external-entity / billion-laughs — use defusedxml")
            break

    # Deduplicate by message text
    seen = set()
    deduped = []
    for f in findings:
        key = f.split(":", 1)[0]
        if key not in seen:
            seen.add(key)
            deduped.append(f)
    return deduped


if __name__ == "__main__":
    main()
