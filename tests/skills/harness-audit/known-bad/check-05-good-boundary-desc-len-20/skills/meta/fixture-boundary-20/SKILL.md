---
name: fixture-boundary-20
description: "12345678901234567890"
---

# fixture-boundary-20

Self-test fixture for check 05 — description is exactly 20 chars (the
`desc_len > 20` boundary) and carries no trigger-pattern clause. The routing
check must stay silent: a description this short carries no routing text at
all, so `desc_len -gt 20` must be false and skip the routing check entirely.
