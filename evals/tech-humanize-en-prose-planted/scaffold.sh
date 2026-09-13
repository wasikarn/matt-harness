#!/usr/bin/env bash
mkdir -p docs
cat > docs/rollout.md <<'FIXTURE_EOF'
# Rollout notes: feature flag for the new checkout

In today's rapidly evolving e-commerce landscape, the new checkout flag stands as a testament to our team's commitment to robust, scalable, and seamless payment experiences. It's not just a flag—it's a foundation. Let's delve into the details.

PR #412 introduced `flags/rollout.py`, which gates the new flow at 5% of traffic—ensuring stability while fostering rapid iteration. On 2026-08-30 the error rate on the gated cohort was 3%, compared to 0.4% on the control, highlighting the intricate interplay between the new address validator and legacy carts.

In conclusion, this rollout underscores the importance of careful, data-driven, and collaborative engineering. I hope this helps! Let me know if you'd like me to expand on any section.
FIXTURE_EOF
