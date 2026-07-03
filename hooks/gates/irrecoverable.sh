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
# Newlines are command separators in bash but shlex eats them as whitespace,
# so a dangerous command after a newline would otherwise hide inside the
# first command's window (found 2026-07-03). Pre-split on \r?\n and tokenize
# each line; '&' (background) is also a separator and is added to OPERATORS.
OPERATORS = {';', '&&', '||', '|', '&'}
windows, cur = [], []
for line in re.split(r'\r?\n', cmd):
    try:
        tokens = shlex.split(line, posix=True)
    except ValueError:
        tokens = line.split()
    for tok in tokens:
        if tok in OPERATORS:
            if cur:
                windows.append(cur)
            cur = []
        else:
            cur.append(tok)
    if cur:
        windows.append(cur)
        cur = []
if cur:
    windows.append(cur)

def basename(p):
    return p.rsplit('/', 1)[-1]

for w in windows:
    if not w:
        continue
    argv0, rest = basename(w[0]), w[1:]

    # sudo/xargs wrap another command — unwrap one level so the checks below
    # still fire. Found 2026-07-01: 'sudo rm -rf x' and 'find | xargs rm -rf'
    # bypassed every check because argv0 was the wrapper, not the wrapped
    # command — and these are everyday shell idioms, not adversarial
    # obfuscation, so they're in scope for a habit-guard.
    if argv0 == 'sudo':
        i = 0
        while i < len(rest) and rest[i].startswith('-'):
            i += 1
        if i < len(rest):
            argv0, rest = basename(rest[i]), rest[i + 1:]
    elif argv0 == 'xargs':
        # Unlike git, xargs args are never a free-text commit message, so
        # scanning for a known-dangerous basename anywhere in its args is
        # safe (no quoted-prose false-positive risk).
        for j, t in enumerate(rest):
            if basename(t) in ('rm', 'find', 'dd'):
                argv0, rest = basename(t), rest[j + 1:]
                break

    if argv0 == 'rm':
        # Lowercase before matching: 'rm -Rf' / 'rm -R -f' bypassed the
        # lowercase-only 'r'/'f' substring check (found 2026-07-01).
        flags = ''.join(t for t in rest if t.startswith('-')).lower()
        if 'r' in flags and 'f' in flags:
            deny('rm -rf detected — use trash instead')

    if argv0 == 'find' and ('-exec' in rest or '-execdir' in rest) and 'rm' in [basename(t) for t in rest]:
        deny('find -exec/-execdir rm detected — destructive delete, use trash or confirm with user')
    if argv0 == 'find' and '-delete' in rest:
        deny('find -delete detected — destructive delete, use trash or confirm with user')

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

        if sub == 'push' and any(
            t in ('-f', '--force') or (t.startswith('--force') and not t.startswith('--force-with-lease'))
            or (t.startswith('-') and not t.startswith('--') and 'f' in t)
            for t in scan
        ):
            deny('git push --force overwrites remote history — needs explicit user approval (use --force-with-lease for the safe variant)')
        if sub == 'reset' and '--hard' in scan:
            deny('git reset --hard discards uncommitted work — confirm with user first')
        if sub == 'clean' and any(t.startswith('-') and 'f' in t for t in scan):
            deny('git clean -f deletes untracked files — confirm with user first')
        if sub == 'checkout' and ('--' in scan or '.' in scan):
            deny('git checkout -- / git checkout . discards working-tree changes — confirm with user first')
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
        if re.search(r'DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE', ' '.join(rest), re.IGNORECASE):
            deny('destructive SQL (DROP TABLE/DATABASE/SCHEMA or TRUNCATE TABLE) detected — confirm with user first')

if '--no-verify' in tokens:
    deny('--no-verify bypasses safety hooks')

sys.exit(0)
"
exit $?
