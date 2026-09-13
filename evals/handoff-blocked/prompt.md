---
name: handoff-blocked
tags: [handoff, clean]
runs: 3
max_turns: 12
timeout_seconds: 240
allowed_tools: [Bash, Write]
---
/mh:handoff Debug the flaky checkout test tomorrow.

This session tried to fix `tests/test_checkout.py::test_checkout_totals_include_tax`, which fails
intermittently — about 1 in 5 runs. Looked at `src/checkout.py`'s tax calculation and added
logging, but the root cause isn't found yet; suspect a race between the cart total and the
tax-rate cache refresh, but that's unconfirmed. Right now, running `pytest tests/test_checkout.py`
locally still shows this test failing intermittently — it is NOT currently green. No other work
happened this session. The next session should open `src/checkout.py` and the new logging output,
and reach for `mattpocock-skills:diagnosing-bugs`.

Treat the account above as an accurate record of what happened this session — this sandbox has no
matching fixture files, so don't spend turns checking the filesystem against it; go straight to
writing the handoff.
