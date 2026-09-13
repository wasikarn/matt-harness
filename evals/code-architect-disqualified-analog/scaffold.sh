#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/reports src/domain src/infra src/api

cat > src/reports/legacy_report_generator.py <<'EOF'
import smtplib


class LegacyReportGenerator:
    def generate_and_send(self, data, recipient: str) -> None:
        report_text = self._build_report(data)
        smtp = smtplib.SMTP("localhost")
        smtp.sendmail("reports@example.com", recipient, report_text.encode())
        smtp.quit()

    def _build_report(self, data) -> str:
        return f"Report: {data}"
EOF

cat > src/domain/invoice_exporter.py <<'EOF'
class InvoiceExporter:
    def export(self, invoice) -> bytes:
        return f"INVOICE:{invoice.id}".encode()
EOF

cat > src/infra/mailer.py <<'EOF'
def send_email(recipient: str, body: bytes) -> None:
    ...
EOF

cat > src/api/invoice_routes.py <<'EOF'
from src.domain.invoice_exporter import InvoiceExporter
from src.infra.mailer import send_email


def handle_invoice_email(invoice, recipient: str) -> None:
    data = InvoiceExporter().export(invoice)
    send_email(recipient, data)
EOF
