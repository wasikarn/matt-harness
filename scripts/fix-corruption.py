#!/usr/bin/env python3
"""Fix the corrupted printf pattern introduced by the buggy echo-to-printf script.

The buggy script turned:
    echo "$VAR" |
into:
    printf '%s\n' "$VAR" |
but because re.sub treats \n as a newline in the replacement string, the actual
output became a literal newline between %s and the closing quote:
    printf '%s
    ' "$VAR" |

This script restores the correct single-line printf '%s\\n' form.
"""
import re, os

# Match the corrupted multi-line pattern.
# In a NORMAL string, \\n in the regex is a literal newline char.
CORRUPT_RE = re.compile("printf '%s\n' (\"\\$[A-Za-z_][A-Za-z0-9_]*\") \\|")

# In the REPLACEMENT raw string, \\n becomes two backslashes in the string value,
# which re.sub interprets as one literal backslash + n = backslash-n in output.
REPL = r"printf '%s\\n' \1 |"

def fix_file(path):
    with open(path, 'r') as f:
        content = f.read()
    fixed = CORRUPT_RE.sub(REPL, content)
    if fixed != content:
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
