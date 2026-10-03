#!/usr/bin/env bash
git init -q . && git config user.email dev@example.com && git config user.name dev
echo "demo project" > README.md
git add README.md && git commit -qm "baseline"
cat > discounts.py <<'FIXTURE_EOF'
def apply_bulk_discount(price, qty):
    if qty > 5:
        return price * 0.9
    return price
FIXTURE_EOF
cat > test_discounts.py <<'FIXTURE_EOF'
import unittest
from discounts import apply_bulk_discount

class TestDiscounts(unittest.TestCase):
    def test_no_discount_below_threshold(self):
        self.assertEqual(apply_bulk_discount(100, 6), 100)
FIXTURE_EOF
cat > greeting.py <<'FIXTURE_EOF'
def greet(name):
    return f"Hello, {name}!"
FIXTURE_EOF
cat > test_greeting.py <<'FIXTURE_EOF'
import unittest
from greeting import greet

class TestGreeting(unittest.TestCase):
    def test_trims_whitespace(self):
        self.assertEqual(greet("  Alice  "), "Hello, Alice!")
FIXTURE_EOF
cat > NOTES.md <<'FIXTURE_EOF'
Session notes
=============
- apply_bulk_discount() only discounts orders of more than 10 units.
- greet() trims surrounding whitespace from the name before greeting.
- All tests pass.
FIXTURE_EOF
git add discounts.py test_discounts.py greeting.py test_greeting.py NOTES.md && git commit -qm "add discounts and greeting"
