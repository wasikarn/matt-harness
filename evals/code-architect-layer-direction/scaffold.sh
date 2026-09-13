#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/domain src/infra src/api

cat > src/domain/exporters.py <<'EOF'
from abc import ABC, abstractmethod


class Exporter(ABC):
    @abstractmethod
    def export(self, invoice: "Invoice") -> bytes:
        ...


class PdfExporter(Exporter):
    def export(self, invoice: "Invoice") -> bytes:
        return f"PDF:{invoice.id}:{invoice.total}".encode()
EOF

cat > src/infra/file_writer.py <<'EOF'
def write_to_disk(path: str, data: bytes) -> None:
    with open(path, "wb") as f:
        f.write(data)
EOF

cat > src/api/export_routes.py <<'EOF'
from src.domain.exporters import PdfExporter
from src.infra.file_writer import write_to_disk


def handle_export_request(invoice, out_path: str) -> None:
    exporter = PdfExporter()
    data = exporter.export(invoice)
    write_to_disk(out_path, data)
EOF
