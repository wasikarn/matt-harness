---
name: fixture-good-leadword
description: "Scan bulk provisioning logs for widget environments needing review. Use when a team requests a compliance check."
---

# fixture-good-leadword

## Steps

1. Set up the environment.
2. Run the scan.
3. Verify the scan output is clean.
4. Confirm findings are triaged.

Self-test fixture for check 34 — description opens with "Scan", which is on
the kbg-native allowlist, so check 34 must stay silent on the leading-word
rule. Body carries a completion-criterion token and >=5 substantive lines
so no other sub-check fires either.
