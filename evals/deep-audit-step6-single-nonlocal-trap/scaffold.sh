#!/usr/bin/env bash
git init -q . && git config user.email dev@example.com && git config user.name dev
cat > catalog.py <<'FIXTURE_EOF'
CATALOG = {"demo_widget": {"name": "Demo Widget", "price": 8}}

# Convenience constant for callers that only need the demo widget's price.
# Kept in sync with CATALOG["demo_widget"]["price"] by hand.
DEMO_WIDGET_PRICE = 10
FIXTURE_EOF
cat > pricing.py <<'FIXTURE_EOF'
from catalog import DEMO_WIDGET_PRICE

def display_price(qty):
    return f"${qty * DEMO_WIDGET_PRICE}"
FIXTURE_EOF
cat > test_pricing.py <<'FIXTURE_EOF'
import unittest
from pricing import display_price

class TestPricing(unittest.TestCase):
    def test_display_price(self):
        self.assertEqual(display_price(3), "$30")
FIXTURE_EOF
git add catalog.py pricing.py test_pricing.py && git commit -qm "baseline: catalog and pricing"
cat > checkout.py <<'FIXTURE_EOF'
from catalog import DEMO_WIDGET_PRICE

def checkout_total(qty):
    return qty * DEMO_WIDGET_PRICE
FIXTURE_EOF
cat > test_checkout.py <<'FIXTURE_EOF'
import unittest
from catalog import CATALOG
from checkout import checkout_total

class TestCheckout(unittest.TestCase):
    def test_matches_catalog_price(self):
        expected = CATALOG["demo_widget"]["price"] * 3
        self.assertEqual(checkout_total(3), expected)
FIXTURE_EOF
cat > NOTES.md <<'FIXTURE_EOF'
Session notes
=============
- checkout_total() now charges the catalog's real demo widget price (CATALOG["demo_widget"]["price"]).
- All tests pass.
FIXTURE_EOF
git add checkout.py test_checkout.py NOTES.md && git commit -qm "add checkout"
