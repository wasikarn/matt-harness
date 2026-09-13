---
type: llm
focus: trace
---
`claim_and_charge` claims a row with `UPDATE orders SET status = 'charging' WHERE id = %s AND
charge_id IS NULL` — the SET column (`status`) does not match the WHERE guard column
(`charge_id`). Two concurrent workers both see `charge_id IS NULL` (it's only set later, in a
second UPDATE) and can both pass the claim guard and both charge the same order. Score 1 if the
report identifies this specific guard-column mismatch as a real double-charge race and proposes
the fix of guarding on the column actually being written (e.g. `WHERE id = %s AND status =
'pending'`) or an equivalent atomic single-column claim. Score 0 if it misses the race entirely,
or flags a generic "add locking" concern without identifying that the WHERE clause guards the
wrong column.
