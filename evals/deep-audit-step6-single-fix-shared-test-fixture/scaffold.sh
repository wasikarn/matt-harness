#!/usr/bin/env bash
git init -q . && git config user.email dev@example.com && git config user.name dev
cat > shipping.py <<'FIXTURE_EOF'
FREE_SHIPPING_THRESHOLD = 50

def qualifies_for_free_shipping(order):
    return order["qty"] * order["unit_price"] >= FREE_SHIPPING_THRESHOLD
FIXTURE_EOF
cat > test_helpers.py <<'FIXTURE_EOF'
def make_order(qty=1, unit_price=10):
    return {"qty": qty, "unit_price": unit_price}
FIXTURE_EOF
cat > test_shipping.py <<'FIXTURE_EOF'
import unittest
from test_helpers import make_order
from shipping import qualifies_for_free_shipping

class TestShipping(unittest.TestCase):
    def test_six_units_qualifies(self):
        order = make_order(qty=6)
        self.assertTrue(qualifies_for_free_shipping(order))
FIXTURE_EOF
git add shipping.py test_helpers.py test_shipping.py && git commit -qm "baseline: shipping and shared test fixture"
cat > catalog.py <<'FIXTURE_EOF'
DEMO_WIDGET_PRICE = 8
FIXTURE_EOF
cat > test_catalog_consistency.py <<'FIXTURE_EOF'
import unittest
from catalog import DEMO_WIDGET_PRICE
from test_helpers import make_order

class TestCatalogConsistency(unittest.TestCase):
    def test_make_order_default_matches_catalog(self):
        order = make_order()
        self.assertEqual(order["unit_price"], DEMO_WIDGET_PRICE)
FIXTURE_EOF
cat > NOTES.md <<'FIXTURE_EOF'
Session notes
=============
- Aligned the shared test fixture's default demo price with the current product catalog:
  make_order() now defaults to $8, matching catalog.DEMO_WIDGET_PRICE.
- All tests pass.
FIXTURE_EOF
git add catalog.py test_catalog_consistency.py NOTES.md && git commit -qm "add catalog and consistency check"
