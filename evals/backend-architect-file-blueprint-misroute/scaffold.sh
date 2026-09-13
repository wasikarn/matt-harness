#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/domain src/infra src/api

cat > src/domain/order.py <<'EOF'
class Order:
    def __init__(self, id: str, customer_id: str, status: str):
        self.id = id
        self.customer_id = customer_id
        self.status = status
EOF

cat > src/infra/order_repository.py <<'EOF'
import db
from src.domain.order import Order


def find_by_customer(customer_id: str) -> list:
    rows = db.query("SELECT * FROM orders WHERE customer_id = %s", (customer_id,))
    return [Order(r["id"], r["customer_id"], r["status"]) for r in rows]
EOF

cat > src/api/order_routes.py <<'EOF'
def get_order(order_id: str) -> dict:
    ...
EOF
