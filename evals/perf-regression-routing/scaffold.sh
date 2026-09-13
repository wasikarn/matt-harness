#!/usr/bin/env bash
set -euo pipefail
mkdir -p src

cat > src/checkout.js <<'EOF'
function calculateShipping(cart) {
  let total = 0;
  for (const item of cart.items) {
    total += item.weight * cart.destination.rate;
  }
  return total;
}

module.exports = { calculateShipping };
EOF
