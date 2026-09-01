---
name: fixture-bad-leadword
description: "Handles bulk provisioning of widget environments for teams. Use when a team needs a fast setup without manual config."
---

# fixture-bad-leadword

## Steps

1. Set up the environment.
2. Run provisioning.
3. Verify the environment boots correctly.
4. Confirm access works as expected.

Self-test fixture for check 34 — description opens with "Handles", not a
matt-vocabulary or kbg-native-allowlisted term, so check 34 must emit an
INFO for the leading-word rule. Body carries a completion-criterion token
(Verify/Confirm) and >=5 substantive lines so the other sub-checks stay
quiet, isolating the leading-word finding.
