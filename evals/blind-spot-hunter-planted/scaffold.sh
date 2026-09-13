#!/usr/bin/env bash
mkdir -p shop
cat > shop/pricing.py <<'FIXTURE_EOF'
def order_total(items) -> int:
    """Return the order total in cents."""
    return sum(i.unit_price_cents * i.qty for i in items)
FIXTURE_EOF
mkdir -p shop
cat > shop/payments.py <<'FIXTURE_EOF'
from shop import pricing
from shop.gateway import Gateway


def pay(order, gateway: Gateway):
    total = pricing.order_total(order.items)
    # Gateway.charge takes the amount in whole currency units (dollars).
    return gateway.charge(amount_dollars=total, currency="USD")
FIXTURE_EOF
mkdir -p shop
cat > shop/gateway.py <<'FIXTURE_EOF'
class Gateway:
    def charge(self, amount_dollars: float, currency: str) -> str:
        """Charge `amount_dollars` (dollars, not cents) and return a transaction id."""
        return f"txn_{currency}_{amount_dollars}"
FIXTURE_EOF
