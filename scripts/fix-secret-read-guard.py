#!/usr/bin/env python3
with open('secret-read-guard.sh', 'r') as f:
    lines = f.read().split('\n')

for i in range(len(lines)):
    if 'STRIPPED=$(printf' in lines[i] and "tr -d '" in lines[i]:
        lines[i-2] = '    # Strip comments, then DELETE quote characters AND backslashes so'
        lines[i-1] = "    # escaped quotes (\\\" or \\') can't hide a secret path."
        lines[i] = "    STRIPPED=$(printf '%s\\n' \"$COMMAND\" | sed -E 's/#.*$//g' | tr -d '\"'\\''\\\\')"
        print(f'fixed line {i+1}')
        break
else:
    print('pattern not found')
    for i, line in enumerate(lines):
        if 'STRIPPED=' in line:
            print(f'{i+1}: {repr(line)}')

with open('secret-read-guard.sh', 'w') as f:
    f.write('\n'.join(lines))
