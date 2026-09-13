#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/services

cat > src/services/order_service.py <<'EOF'
import db


def create_order(customer_id: str, items: list) -> str:
    order_id = db.new_id()
    db.execute(
        "INSERT INTO orders (id, customer_id, status) VALUES (%s, %s, 'pending')",
        (order_id, customer_id),
    )
    return order_id


def cancel_order(order_id: str) -> None:
    db.execute("UPDATE orders SET status = 'cancelled' WHERE id = %s", (order_id,))
EOF

cat > src/services/fulfillment_service.py <<'EOF'
import db


def mark_shipped(order_id: str, tracking_number: str) -> None:
    db.execute(
        "UPDATE orders SET status = 'shipped', tracking_number = %s WHERE id = %s",
        (tracking_number, order_id),
    )


def mark_delivered(order_id: str) -> None:
    db.execute("UPDATE orders SET status = 'delivered' WHERE id = %s", (order_id,))
EOF
