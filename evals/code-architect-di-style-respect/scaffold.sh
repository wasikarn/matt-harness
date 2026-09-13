#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/services src/infra src/api

cat > src/infra/db.py <<'EOF'
class Database:
    def save(self, record) -> None: ...
    def mark_refunded(self, order_id) -> None: ...
    def update_status(self, order_id, status) -> None: ...
EOF

cat > src/infra/mailer.py <<'EOF'
class Mailer:
    def send(self, to: str, subject: str) -> None: ...
EOF

cat > src/infra/payment_gateway.py <<'EOF'
class PaymentGateway:
    def refund(self, order_id, amount) -> None: ...
EOF

cat > src/services/order_service.py <<'EOF'
class OrderService:
    def __init__(self, db, mailer):
        self.db = db
        self.mailer = mailer

    def place_order(self, order) -> None:
        self.db.save(order)
        self.mailer.send(order.customer_email, "Order placed")
EOF

cat > src/services/refund_service.py <<'EOF'
class RefundService:
    def __init__(self, db, payment_gateway):
        self.db = db
        self.payment_gateway = payment_gateway

    def process_refund(self, order_id, amount) -> None:
        self.payment_gateway.refund(order_id, amount)
        self.db.mark_refunded(order_id)
EOF

cat > src/api/wiring.py <<'EOF'
from src.services.order_service import OrderService
from src.services.refund_service import RefundService
from src.infra.db import Database
from src.infra.mailer import Mailer
from src.infra.payment_gateway import PaymentGateway

db = Database()
mailer = Mailer()
payment_gateway = PaymentGateway()

order_service = OrderService(db, mailer)
refund_service = RefundService(db, payment_gateway)
EOF
