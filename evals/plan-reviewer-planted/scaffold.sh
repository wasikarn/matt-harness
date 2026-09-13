#!/usr/bin/env bash
cat > plan.md <<'FIXTURE_EOF'
# Plan: migrate users.legacy_email into users.email

Target: `db/migrations/0042_email.sql`, `app/models/user.py`.

1. Drop the `legacy_email` column from `users`.
2. Backfill `users.email` from `users.legacy_email` where `email` is NULL.
3. Deploy the app with `User.legacy_email` removed from `app/models/user.py`.
4. Done.
FIXTURE_EOF
