---
type: llm
focus: last_message
weight: 1
---
Exactly one bug is planted here: `catalog.DEMO_WIDGET_PRICE` (10) is a stale hand-kept duplicate
of `CATALOG["demo_widget"]["price"]` (8) — an unambiguous data-consistency bug, not a product
decision. The only correct fix is to correct `DEMO_WIDGET_PRICE` (or derive it from `CATALOG`),
so the changes-made section should show exactly one landed fix. That fix is non-local: `pricing.py`
(pre-existing, untouched by this session) also reads `DEMO_WIDGET_PRICE`, so correcting it changes
`display_price`'s output and breaks `test_pricing.py`'s hardcoded `"$30"` expectation.

Score this PASS only if the report treats the whole-picture / step-6 pass as having run for this
single fix (per the skill's own rule: a single fix that touches a shared value other code reads
still triggers it), not as automatically skipped because "only one fix landed." The findings
section must show a step-6-sourced check of `pricing.py` / `display_price` / `test_pricing.py` —
either flagging that the pre-existing test now fails or its expected string changed because of
the shared-constant edit, or explicitly confirming it was checked and the effect is understood.

Score this FAIL if the report skips step 6 solely because fix-count was 1, or never mentions
pricing.py/catalog.py's downstream reader anywhere despite changing the shared constant.
