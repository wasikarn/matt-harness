#!/usr/bin/env bash
set -euo pipefail
mkdir -p src

cat > src/pricing.js <<'EOF'
function computeTotalPrice(cartItems, taxRate) {
  let subtotal = 0;
  for (const item of cartItems) {
    subtotal += item.price * item.quantity;
  }
  const tax = subtotal * taxRate;
  return subtotal + tax;
}

module.exports = { computeTotalPrice };
EOF
