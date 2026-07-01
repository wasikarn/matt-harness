#!/usr/bin/env bash
# Gate: block irrecoverable Bash patterns before they execute.
# Reads the PreToolUse JSON payload from stdin; exits 2 to block.
set -uo pipefail

python3 -c "
import json, re, shlex, sys

try:
    d = json.load(sys.stdin)
    cmd = d.get('tool_input', {}).get('command', '')
except Exception:
    cmd = ''

def deny(reason):
    print(f'[kbg:gate] BLOCKED: {reason}', file=sys.stderr)
    sys.exit(2)

# Tokenize respecting quotes: 'rm' and the word rm both resolve to a bare
# rm token, and quoted free text (commit messages, grep patterns) stays
# inside one token instead of being scanned as if it were a command.
# ponytail: no command-substitution/eval unwrapping here — this is a
# habit-guard for a single-operator harness, not an adversarial sandbox;
# revisit if that threat model changes.
try:
    tokens = shlex.split(cmd, posix=True)
except ValueError:
    tokens = cmd.split()

OPERATORS = {';', '&&', '||', '|'}
windows, cur = [], []
for tok in tokens:
    if tok in OPERATORS:
        if cur:
            windows.append(cur)
        cur = []
    else:
        cur.append(tok)
if cur:
    windows.append(cur)

def basename(p):
    return p.rsplit('/', 1)[-1]

for w in windows:
    if not w:
        continue
    argv0, rest = basename(w[0]), w[1:]

    if argv0 == 'rm':
        flags = ''.join(t for t in rest if t.startswith('-'))
        if 'r' in flags and 'f' in flags:
            deny('rm -rf detected — use trash instead')

    if argv0 == 'find' and '-exec' in rest and 'rm' in [basename(t) for t in rest]:
        deny('find -exec rm detected — destructive delete, use trash or confirm with user')

    if argv0 == 'git' and rest:
        sub, args = rest[0], rest[1:]
        # drop the value token after a free-text flag so message content
        # (e.g. commit -m '...rm -rf...') is never pattern-matched.
        scan, skip = [], False
        for t in args:
            if skip:
                skip = False
                continue
            if t in ('-m', '--message'):
                skip = True
                continue
            scan.append(t)

        if sub == 'push' and any(t in ('-f', '--force') for t in scan):
            deny('git push --force overwrites remote history — needs explicit user approval')
        if sub == 'reset' and '--hard' in scan:
            deny('git reset --hard discards uncommitted work — confirm with user first')
        if sub == 'clean' and any(t.startswith('-') and 'f' in t for t in scan):
            deny('git clean -f deletes untracked files — confirm with user first')
        if sub == 'checkout' and '--' in scan:
            deny('git checkout -- discards working-tree changes — confirm with user first')
        if sub == 'switch' and any(t in ('-f', '--force', '--discard-changes') for t in scan):
            deny('git switch --force discards working-tree changes — confirm with user first')
        if sub == 'commit' and '--amend' in scan:
            deny('git commit --amend rewrites history — confirm with user first')
        if sub == 'add' and any(t in ('-A', '--all', '.') for t in scan):
            deny('git add -A/. stages everything — stage files by name instead')

    if argv0 == 'dd' and any(t.startswith('of=/dev/') for t in rest):
        deny('dd writing to a raw device — irrecoverable disk-level destruction')

    if argv0 in ('mysql', 'psql', 'sqlite3'):
        # SQL genuinely lives inside -e/-c values, unlike git's free-text
        # messages — deliberately DO scan inside those here.
        if re.search(r'DROP\s+(TABLE|DATABASE)', ' '.join(rest), re.IGNORECASE):
            deny('destructive SQL (DROP TABLE/DATABASE) detected — confirm with user first')

if '--no-verify' in tokens:
    deny('--no-verify bypasses safety hooks')

sys.exit(0)
"
exit $?
