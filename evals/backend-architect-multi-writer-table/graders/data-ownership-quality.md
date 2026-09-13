---
type: llm
focus: trace
---
Both `order_service.py` and `fulfillment_service.py` run raw SQL directly against the same
`orders` table (`INSERT`/`UPDATE ... orders`) — no single module owns writes to it. Once split
into separate deployables this becomes two services writing the same table without coordination
(lost updates, no shared transaction, schema changes breaking the other service silently). Score 1
if the report identifies this as a data-ownership violation and recommends fulfillment go through
an API/interface owned by the order service (or an equivalent single-writer boundary) instead of
writing `orders` directly. Score 0 if it doesn't flag the shared direct-write pattern as a problem
for the planned split.
