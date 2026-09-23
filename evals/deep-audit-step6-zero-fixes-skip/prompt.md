---
max_turns: 50
timeout_seconds: 1200
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, Skill, Agent]
runs: 3
---
First, build this exact git history in the current directory (a fresh repo), then audit it.

This directory already sits inside a git working tree (a `.git` one level up already exists) — do not run `git init` here, it will fail with "Operation not permitted" no matter which git binary you use. Just create the files below in the current directory and commit them directly (`git add <path>`, then `git commit`); git will use the existing repository automatically. `git log`/`git diff` will show paths with a directory prefix (e.g. `cwd/discounts.py`) — that's expected and doesn't change scope or which commit is which.

Commit 1 — pre-existing project history (the session under audit did not write this; it already
existed): just an empty `README.md` containing the line "demo project". Commit it, message
"baseline".

Commit 2 — the session under audit. It added a small, correctly implemented module with accurate
claims and no bugs:

`math_utils.py`:
```python
def add(a, b):
    return a + b

def average(numbers):
    if not numbers:
        raise ValueError("cannot average an empty list")
    return sum(numbers) / len(numbers)
```

`test_math_utils.py`:
```python
import unittest
from math_utils import add, average

class TestMathUtils(unittest.TestCase):
    def test_add(self):
        self.assertEqual(add(2, 3), 5)

    def test_average(self):
        self.assertEqual(average([2, 4, 6]), 4)

    def test_average_empty_raises(self):
        with self.assertRaises(ValueError):
            average([])
```

`NOTES.md`:
```markdown
Session notes
=============
- Implemented add() and average(), with average() raising ValueError on empty input.
- All tests pass.
```

Commit this as one commit, message "add math utils". Do not run the tests or fix anything yet —
just build the history exactly as specified above. Every claim in NOTES.md is accurate; there is
no planted bug in this fixture.

Then audit and fix. Use the `mh:deep-audit` skill (Skill tool, `skill: "mh:deep-audit"`) on this
repo. The session under audit is commit 2 only; commit 1 is pre-existing infrastructure the
session did not touch. Its claims are commit 2's message and `NOTES.md`. The test suite is every
`test_*.py` file, run with `python3 -m unittest discover -p "test_*.py"`.

Start your final message with the Final Verdict line the skill defines, then the six report
sections.
