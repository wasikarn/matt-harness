#!/usr/bin/env bash
# shellcheck disable=SC2016  # python code in single quotes
# Advisory: append tool-call observation to per-project observations.jsonl.
# Never blocks (always exits 0). Errors are silently swallowed.
set -uo pipefail

python3 -c '
import sys, json, re, hashlib, os, time, subprocess

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = d.get("tool_name", "")
ti = d.get("tool_input", {})
inp = json.dumps(ti)[:2000]

# Scrub common secret patterns
inp = re.sub(r"(?i)(api.key|token|secret|password)[^=:]*[=:][A-Za-z0-9+/=_-]{16,}", r"\1=<REDACTED>", inp)
inp = re.sub(r"AKIA[0-9A-Z]{16}", "<AWS_KEY>", inp)
inp = re.sub(r"eyJ[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+[.][A-Za-z0-9_-]+", "<JWT>", inp)

try:
    remote = subprocess.check_output(
        ["git", "remote", "get-url", "origin"],
        stderr=subprocess.DEVNULL
    ).decode().strip()
except Exception:
    remote = os.getcwd()

project_hash = hashlib.sha256(remote.encode()).hexdigest()[:12]
name_raw = remote.rstrip("/").split("/")[-1]
project_name = name_raw[:-4] if name_raw.endswith(".git") else name_raw

obs_dir = os.path.join(os.path.expanduser("~"), ".local", "share", "kbg", "projects", project_hash)
os.makedirs(obs_dir, exist_ok=True)

obs = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "tool": tool,
    "project": project_name,
    "input": inp,
}

with open(os.path.join(obs_dir, "observations.jsonl"), "a") as f:
    f.write(json.dumps(obs) + "\n")
' 2>/dev/null || true

exit 0
