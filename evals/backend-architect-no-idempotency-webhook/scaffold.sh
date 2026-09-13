#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/webhooks docs

cat > src/webhooks/payment_webhook.py <<'EOF'
import db
import mailer


def handle_stripe_webhook(payload: dict) -> None:
    event_type = payload["type"]
    if event_type != "charge.succeeded":
        return

    order_id = payload["data"]["order_id"]
    db.execute("UPDATE orders SET status = 'paid' WHERE id = %s", (order_id,))
    mailer.send_confirmation_email(order_id)
EOF

cat > docs/stripe-webhook-notes.md <<'EOF'
Stripe retries webhook deliveries with exponential backoff until our endpoint returns 2xx.
We currently always return 200 immediately, but Stripe may still redeliver the same event
(duplicate deliveries, network retries on their side, etc.) per their own docs.
EOF
