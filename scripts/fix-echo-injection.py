#!/usr/bin/env python3
"""
Fix echo "$VAR" flag-injection across hook scripts.
Replaces piped standalone echo with printf '%s\n', preserving the variable name.
"""
import re, os

# Match: echo "$VAR" |  (and capture $VAR)
ECHO_PIPED_RE = re.compile(r'\becho\s+"(\$[A-Za-z_][A-Za-z0-9_]*)"\s*\|')

# Replacement: printf '%s\n' "$VAR" |
# NOTE: NOT a raw string so \" becomes " and \1 is the backreference.
REPL = "printf '%s\\n' \"\\1\" |"

def fix_file(path):
    with open(path, 'r') as f:
        original = f.read()
    fixed = ECHO_PIPED_RE.sub(REPL, original)
    if fixed != original:
        with open(path, 'w') as f:
            f.write(fixed)
        return True
    return False

if __name__ == '__main__':
    changed = 0
    for fn in sorted(os.listdir('.')):
        if fn.endswith('.sh'):
            if fix_file(fn):
                print(f'fixed: {fn}')
                changed += 1
    print(f'Total files changed: {changed}')
