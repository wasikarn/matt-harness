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
import pytest

from src.discount import apply_discount


def test_ten_percent_off():
    assert apply_discount(1000, 10) == 900


def test_boundaries_zero_and_full():
    assert apply_discount(1000, 0) == 1000
    assert apply_discount(1000, 100) == 0


@pytest.mark.parametrize("pct", [-1, 101])
def test_out_of_range_pct_raises(pct):
    with pytest.raises(ValueError):
        apply_discount(1000, pct)


def test_negative_price_raises():
    with pytest.raises(ValueError):
        apply_discount(-1, 10)


def test_rounds_half_cent():
    assert apply_discount(999, 5) == 949
FIXTURE_EOF
