---
type: llm
focus: trace
---
`create_charge` takes `priceCents` straight from the client request body and charges that amount,
even though `src/catalog/catalog.py` already exposes `get_price_cents(item_id)` as the real price
source — the checkout service never calls it. A client can charge any amount they want by editing
the request. Score 1 if the report identifies that the charge amount must be re-derived
server-side from the catalog (or another trusted source) rather than trusted from client input,
naming this as a financial-integrity / source-of-truth violation. Score 0 if it reviews the
endpoint without flagging that the price is attacker-controlled.
