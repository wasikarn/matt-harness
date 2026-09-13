#!/usr/bin/env bash
set -euo pipefail
mkdir -p src

cat > src/dedupe.js <<'EOF'
function findDuplicates(items, otherItems) {
  const duplicates = [];
  for (const item of items) {
    for (const other of otherItems) {
      if (item.id === other.id) {
        duplicates.push(item);
        break;
      }
    }
  }
  return duplicates;
}

module.exports = { findDuplicates };
EOF

cat > bench.js <<'EOF'
const { findDuplicates } = require('./src/dedupe');

const items = Array.from({ length: 4000 }, (_, i) => ({ id: i }));
const otherItems = Array.from({ length: 4000 }, (_, i) => ({ id: i * 2 }));

const start = Date.now();
const result = findDuplicates(items, otherItems);
const end = Date.now();
console.log(`findDuplicates: ${end - start}ms, ${result.length} matches, ${items.length}x${otherItems.length} items`);
EOF
