#!/usr/bin/env python3
import re
with open('block-dangerous-git.sh', 'r') as f:
    content = f.read()
m = re.search(r"printf '%s.*n'", content, re.DOTALL)
if m:
    start = max(0, m.start() - 20)
    end = min(len(content), m.end() + 40)
    print(repr(content[start:end]))
else:
    print('No match found')
    lines = content.split('\n')
    for i in range(20, 26):
        print(f'{i+1}: {repr(lines[i])}')
