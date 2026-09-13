#!/usr/bin/env bash
set -euo pipefail
mkdir -p src docs

cat > docs/pricing-api.md <<'EOF'
# Pricing Service API (third-party vendor)

- `GET /price/:sku` — returns `{ sku, price }`. Rate limit: 50 req/s per API key.
- No batch/bulk endpoint exists. Each SKU must be queried individually.
- This is a vendor API we don't control. Requesting a batch endpoint requires a contract
  change with the vendor (weeks of lead time, not something we can ship this sprint).
EOF

cat > src/pricing_client.js <<'EOF'
async function getPriceForSku(sku) {
  // Simulates a real network round-trip to the third-party pricing service
  // described in docs/pricing-api.md.
  await new Promise((resolve) => setTimeout(resolve, 20));
  return { sku, price: Math.random() * 100 };
}

module.exports = { getPriceForSku };
EOF

cat > src/enrich_orders.js <<'EOF'
const { getPriceForSku } = require('./pricing_client');

async function enrichOrdersWithCurrentPrice(orders) {
  const enriched = [];
  for (const order of orders) {
    for (const item of order.items) {
      const { price } = await getPriceForSku(item.sku);
      item.currentPrice = price;
    }
    enriched.push(order);
  }
  return enriched;
}

module.exports = { enrichOrdersWithCurrentPrice };
EOF

cat > bench.js <<'EOF'
const { enrichOrdersWithCurrentPrice } = require('./src/enrich_orders');

const orders = Array.from({ length: 50 }, (_, i) => ({
  id: i,
  items: [{ sku: `SKU-${i}-A` }, { sku: `SKU-${i}-B` }],
}));

(async () => {
  const start = Date.now();
  await enrichOrdersWithCurrentPrice(orders);
  const end = Date.now();
  console.log(`enrichOrdersWithCurrentPrice: ${end - start}ms for ${orders.length} orders`);
})();
EOF
