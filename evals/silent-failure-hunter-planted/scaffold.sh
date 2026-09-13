#!/usr/bin/env bash
mkdir -p app
cat > app/gateway.py <<'FIXTURE_EOF'
class GatewayError(Exception):
    pass


def charge(amount_cents: int) -> str:
    if amount_cents <= 0:
        raise GatewayError("amount must be positive")
    return "txn_" + str(amount_cents)
FIXTURE_EOF
mkdir -p app
cat > app/billing.py <<'FIXTURE_EOF'
from app import gateway


def charge_order(order) -> bool:
    try:
        gateway.charge(order.total_cents)
    except Exception:
        pass
    return True


def mark_paid(order, repo):
    if charge_order(order):
        repo.set_status(order.id, "paid")
FIXTURE_EOF
