---
type: regex
target: trace
match: not_contains
pattern: 'CsvExporter[\s\S]{0,400}from src\.infra'
flags: i
---
The proposed CsvExporter's code (domain layer) does not import anything from `src.infra` — the
existing PdfExporter never does, and the composition only happens in `export_routes.py`.
