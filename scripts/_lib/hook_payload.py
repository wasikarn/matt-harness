"""hook_payload.py -- shared session_id validation for hook payloads.

Imported BY PATH (sys.path[0] = this file's own directory) by
scripts/_lib/fragments_arm_parse.py and fragments_capture_parse.py. (Also
run as a standalone script by hooks/session/handoff-nudge.sh, which needed
only the session id and nothing else from the payload -- that hook and the
mh:handoff skill it belonged to were removed; see git history.) One
definition so the character-class regex and the "." / ".." rejection can't
drift apart between call sites (docs/adr/0003-writing-fragments-pointer-capture.md).

validate_session_id must run on the untruncated JSON value, before it ever
crosses into bash: bash command substitution unconditionally strips
trailing newlines and silently drops embedded NUL bytes, so a value like
"foo\\n" or "foo\\x00bar" would otherwise pass a bash-side regex as a
mangled "foo"/"foobar". This only holds if the raw payload bytes reach this
module without first passing through a bash variable -- compliance-audit
finding, live-reproduced (2026-09-10): fragments-arm.sh and
fragments-capture.sh used to capture stdin into a bash variable
(`PAYLOAD=$(cat)`) before piping it here, which already dropped an embedded
NUL at that step, before this module ever saw it. Both hooks now capture
stdin to a temp FILE instead and feed that file to this module directly,
so the guarantee this docstring describes actually holds end to end.
"""
import re

_SESSION_ID_RE = re.compile(r"[A-Za-z0-9._-]+")


def validate_session_id(value):
    """Return value if it is a valid session id, else "".

    A wrong-typed value (None, a number, a list/dict) is deliberately not
    stringified -- Python's own str() would turn None into "None", which
    would then pass the character-class check as if it were a real id.
    """
    if not isinstance(value, str):
        return ""
    if value in (".", ".."):
        return ""
    if not _SESSION_ID_RE.fullmatch(value):
        return ""
    return value


if __name__ == "__main__":
    import json
    import sys

    try:
        data = json.load(sys.stdin)
    except Exception:
        data = None
    sid = data.get("session_id") if isinstance(data, dict) else None
    print(validate_session_id(sid))
