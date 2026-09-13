#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/auth

cat > src/auth/login.py <<'EOF'
import db


def login(username: str, password: str) -> bool:
    query = "SELECT password FROM users WHERE username = '" + username + "'"
    row = db.query_one(query)
    if row is None:
        return False
    return row["password"] == password
EOF
