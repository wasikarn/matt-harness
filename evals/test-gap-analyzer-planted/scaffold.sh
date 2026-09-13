#!/usr/bin/env bash
mkdir -p src
cat > src/discount.py <<'FIXTURE_EOF'
def apply_discount(price_cents: int, pct: int) -> int:
    if pct < 0 or pct > 100:
        raise ValueError("pct must be within 0..100")
    if price_cents < 0:
        raise ValueError("price must be non-negative")
    return round(price_cents * (100 - pct) / 100)
FIXTURE_EOF
mkdir -p tests
: > tests/__init__.py
cat > tests/test_discount.py <<'FIXTURE_EOF'
from src.discount import apply_discount


def test_ten_percent_off():
    assert apply_discount(1000, 10) == 900
FIXTURE_EOF
