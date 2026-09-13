---
type: regex
target: {source: file, path: src/greeting.py}
match: not_contains
pattern: 'usr'
---
The rename is actually complete: no leftover `usr` anywhere in the file (a half-rename — signature
changed to `user` but the `return` still references `usr` — would raise `NameError` at call time
and previously passed every other grader here, since none of them checked the file's content).
