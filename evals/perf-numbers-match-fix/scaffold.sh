#!/usr/bin/env bash
set -euo pipefail
mkdir -p src

cat > src/leaderboard.js <<'EOF'
class Leaderboard {
  constructor() {
    this.scores = [];
  }

  addScore(score) {
    this.scores.push(score);
  }

  currentMin() {
    // Re-sorts the whole array on every call just to read the minimum.
    this.scores.sort((a, b) => a - b);
    return this.scores[0];
  }
}

module.exports = { Leaderboard };
EOF

cat > bench.js <<'EOF'
const { Leaderboard } = require('./src/leaderboard');

const lb = new Leaderboard();
const start = Date.now();
for (let i = 0; i < 5000; i++) {
  lb.addScore(Math.floor(Math.random() * 1000000));
  lb.currentMin();
}
const end = Date.now();
console.log(`5000 addScore+currentMin cycles: ${end - start}ms`);
EOF
