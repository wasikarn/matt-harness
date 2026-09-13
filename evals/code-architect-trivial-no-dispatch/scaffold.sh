#!/usr/bin/env bash
set -euo pipefail
mkdir -p src

cat > src/greeting.py <<'EOF'
def greet(usr):
    return f"Hello, {usr}!"
EOF
