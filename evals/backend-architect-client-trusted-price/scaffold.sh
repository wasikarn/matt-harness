#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/catalog src/checkout

cat > src/catalog/catalog.py <<'EOF'
import db


def get_price_cents(item_id: str) -> int:
    row = db.query_one("SELECT price_cents FROM items WHERE id = %s", (item_id,))
    return row["price_cents"]
EOF

cat > src/checkout/checkout_service.py <<'EOF'
import payment_client


def create_charge(request_body: dict) -> dict:
    item_id = request_body["itemId"]
    price_cents = request_body["priceCents"]
    customer_id = request_body["customerId"]

    charge = payment_client.charge(amount_cents=price_cents, customer=customer_id)
    return {"chargeId": charge.id, "itemId": item_id, "amount": price_cents}
EOF

cat > src/checkout/routes.py <<'EOF'
from src.checkout.checkout_service import create_charge


def post_checkout(request_body: dict) -> dict:
    return create_charge(request_body)
EOF
