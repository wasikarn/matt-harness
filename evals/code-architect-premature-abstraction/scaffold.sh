#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/notifications src/api

cat > src/notifications/email_notifier.py <<'EOF'
def send_email_notification(user_email: str, message: str) -> None:
    print(f"Sending email to {user_email}: {message}")
EOF

cat > src/api/notify_routes.py <<'EOF'
from src.notifications.email_notifier import send_email_notification


def handle_notify_request(user_email: str, message: str) -> None:
    send_email_notification(user_email, message)
EOF
