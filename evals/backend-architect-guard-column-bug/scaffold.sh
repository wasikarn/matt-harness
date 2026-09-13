#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/billing

cat > src/billing/schema.sql <<'EOF'
CREATE TABLE orders (
    id TEXT PRIMARY KEY,
    status TEXT NOT NULL DEFAULT 'pending',
    charge_id TEXT
);
EOF

cat > src/billing/charge_worker.py <<'EOF'
import db
import payment_client


def claim_and_charge(order_id: str) -> None:
    row = db.execute(
        """
        UPDATE orders
        SET status = 'charging'
        WHERE id = %s AND charge_id IS NULL
        RETURNING id
        """,
        (order_id,),
    )
    if row is None:
        return

    charge_id = payment_client.charge(order_id)
    db.execute(
        "UPDATE orders SET charge_id = %s WHERE id = %s",
        (charge_id, order_id),
    )
EOF
