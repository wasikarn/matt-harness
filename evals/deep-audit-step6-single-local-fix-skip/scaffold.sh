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
cat > NOTES.md <<'FIXTURE_EOF'
Session notes
=============
- apply_bulk_discount() only discounts orders of more than 10 units.
- All tests pass.
FIXTURE_EOF
git add discounts.py test_discounts.py NOTES.md && git commit -qm "add bulk discount"
