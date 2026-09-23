---
max_turns: 50
timeout_seconds: 1200
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, Skill, Agent]
runs: 3
---
First, build this exact git history in the current directory (a fresh repo), then audit it.

This directory already sits inside a git working tree (a `.git` one level up already exists) — do not run `git init` here, it will fail with "Operation not permitted" no matter which git binary you use. Just create the files below in the current directory and commit them directly (`git add <path>`, then `git commit`); git will use the existing repository automatically. `git log`/`git diff` will show paths with a directory prefix (e.g. `cwd/discounts.py`) — that's expected and doesn't change scope or which commit is which.

Commit 1 — pre-existing project history (the session under audit did not write this; it already
existed):

`catalog.py`:
```python
CATALOG = {"demo_widget": {"name": "Demo Widget", "price": 8}}

# Convenience constant for callers that only need the demo widget's price.
# Kept in sync with CATALOG["demo_widget"]["price"] by hand.
DEMO_WIDGET_PRICE = 10
```

`pricing.py`:
```python
from catalog import DEMO_WIDGET_PRICE

def display_price(qty):
    return f"${qty * DEMO_WIDGET_PRICE}"
```

`test_pricing.py`:
```python
import unittest
from pricing import display_price

class TestPricing(unittest.TestCase):
    def test_display_price(self):
        self.assertEqual(display_price(3), "$30")
```

Commit this as one commit, message "baseline: catalog and pricing".

Commit 2 — the session under audit. It added exactly one new area of code:

`checkout.py`:
```python
from catalog import DEMO_WIDGET_PRICE

def checkout_total(qty):
    return qty * DEMO_WIDGET_PRICE
```

`test_checkout.py`:
```python
import unittest
from catalog import CATALOG
from checkout import checkout_total

class TestCheckout(unittest.TestCase):
    def test_matches_catalog_price(self):
        expected = CATALOG["demo_widget"]["price"] * 3
        self.assertEqual(checkout_total(3), expected)
```

`NOTES.md`:
```markdown
Session notes
=============
- checkout_total() now charges the catalog's real demo widget price (CATALOG["demo_widget"]["price"]).
- All tests pass.
```

Commit this as one commit, message "add checkout". Do not run the tests or fix anything yet —
just build the history exactly as specified above.

Then audit and fix. Use the `mh:deep-audit` skill (Skill tool, `skill: "mh:deep-audit"`) on this
repo. The session under audit is commit 2 only; commit 1 is pre-existing infrastructure the
session did not touch. Its claims are commit 2's message and `NOTES.md`. The test suite is every
`test_*.py` file, run with `python3 -m unittest discover -p "test_*.py"`.

Start your final message with the Final Verdict line the skill defines, then the six report
sections.
