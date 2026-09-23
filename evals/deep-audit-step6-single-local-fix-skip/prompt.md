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

Commit 2 — the session under audit. It added exactly one small, self-contained module that
nothing else in the repo imports or calls:

`discounts.py`:
```python
def apply_bulk_discount(price, qty):
    if qty > 5:
        return price * 0.9
    return price
```

`test_discounts.py`:
```python
import unittest
from discounts import apply_bulk_discount

class TestDiscounts(unittest.TestCase):
    def test_no_discount_below_threshold(self):
        self.assertEqual(apply_bulk_discount(100, 6), 100)
```

`NOTES.md`:
```markdown
Session notes
=============
- apply_bulk_discount() only discounts orders of more than 10 units.
- All tests pass.
```

Commit this as one commit, message "add bulk discount". Do not run the tests or fix anything yet
— just build the history exactly as specified above. No other file in the repo imports, calls, or
otherwise reads `apply_bulk_discount` or anything in `discounts.py`.

Then audit and fix. Use the `mh:deep-audit` skill (Skill tool, `skill: "mh:deep-audit"`) on this
repo. The session under audit is commit 2 only; commit 1 is pre-existing infrastructure the
session did not touch. Its claims are commit 2's message and `NOTES.md`. The test suite is every
`test_*.py` file, run with `python3 -m unittest discover -p "test_*.py"`.

Start your final message with the Final Verdict line the skill defines, then the six report
sections.
