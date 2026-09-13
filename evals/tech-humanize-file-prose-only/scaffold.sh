#!/usr/bin/env bash
cat > README.md <<'FIXTURE_EOF'
---
title: cache-warmer
owner: platform
---
# cache-warmer

In today's fast-paced infrastructure landscape, cache-warmer serves as a robust, elegant, and indispensable tool—ensuring that cold starts are a thing of the past. Let's delve into how it works.

```bash
# warm every region — takes ~4 min
cache-warmer --regions all --force
```

Run it after each deploy. It reads `regions.yaml` and hits `/warm` on each edge node.
FIXTURE_EOF
