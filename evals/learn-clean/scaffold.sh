#!/usr/bin/env bash
mkdir -p memory
cat > memory/MEMORY.md <<'FIXTURE_EOF'
# Memory index

(empty store — nothing indexed yet)
FIXTURE_EOF
cat > transcript.jsonl <<'FIXTURE_EOF'
{"type":"user","message":{"role":"user","content":"what does this function do on line 40"}}
{"type":"assistant","message":{"role":"assistant","content":"It parses the config file and returns a dict."}}
{"type":"user","message":{"role":"user","content":"ok, fix the missing semicolon on line 12"}}
{"type":"assistant","message":{"role":"assistant","content":"Fixed."}}
{"type":"user","message":{"role":"user","content":"thanks, that's all for today"}}
FIXTURE_EOF
