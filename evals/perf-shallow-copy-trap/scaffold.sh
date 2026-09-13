#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/handlers

cat > src/settings.js <<'EOF'
function cloneUserSettings(settings) {
  return JSON.parse(JSON.stringify(settings));
}

module.exports = { cloneUserSettings };
EOF

cat > src/handlers/update_theme.js <<'EOF'
const { cloneUserSettings } = require('../settings');

function updateTheme(original, newTheme) {
  const copy = cloneUserSettings(original);
  copy.preferences.theme = newTheme;
  return copy;
}

module.exports = { updateTheme };
EOF

cat > bench.js <<'EOF'
const { cloneUserSettings } = require('./src/settings');

const settings = {
  userId: 42,
  preferences: { theme: 'light', fontSize: 14, notifications: { email: true, sms: false } },
};

const start = Date.now();
for (let i = 0; i < 200000; i++) {
  cloneUserSettings(settings);
}
const end = Date.now();
console.log(`cloneUserSettings x200000: ${end - start}ms`);
EOF
