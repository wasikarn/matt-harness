#!/usr/bin/env bash
mkdir -p memory
cat > memory/MEMORY.md <<'FIXTURE_EOF'
# Memory index

(empty store — nothing indexed yet)
FIXTURE_EOF
cat > transcript.jsonl <<'FIXTURE_EOF'
{"type":"user","message":{"role":"user","content":"can you run the seed script to set up test data"}}
{"type":"assistant","message":{"role":"assistant","content":"Running scripts/seed.sh now."}}
{"type":"user","message":{"role":"user","content":"no, wait -- always pass --dry-run first when touching migrations in this repo, we broke staging twice running one live without checking"}}
{"type":"assistant","message":{"role":"assistant","content":"Understood, I'll always run migrations with --dry-run first here."}}
{"type":"user","message":{"role":"user","content":"can you run the seed script again, the data got wiped"}}
{"type":"assistant","message":{"role":"assistant","content":"Running scripts/seed.sh again."}}
{"type":"user","message":{"role":"user","content":"also fix that typo in the comment on line 12, should be receive not recieve"}}
{"type":"assistant","message":{"role":"assistant","content":"Fixed the typo."}}
FIXTURE_EOF
