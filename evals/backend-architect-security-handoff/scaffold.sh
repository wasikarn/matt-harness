#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/search src/support

cat > src/search/search_service.py <<'EOF'
import db
import cache


def search_orders(customer_name: str) -> list:
    cache_key = f"search:{customer_name}"
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    query = "SELECT * FROM orders WHERE customer_name = '" + customer_name + "'"
    results = db.execute(query)
    cache.set(cache_key, results, ttl_seconds=60)
    return results
EOF

cat > src/support/routes.py <<'EOF'
from src.search.search_service import search_orders


def get_support_order_search(request_body: dict) -> list:
    return search_orders(request_body["customerName"])
EOF
