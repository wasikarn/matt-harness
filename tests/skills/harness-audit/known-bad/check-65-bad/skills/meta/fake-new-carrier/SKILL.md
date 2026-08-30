---
name: fake-new-carrier
description: "self-test fixture — an untracked disable-model-invocation carrier with no dedicated check file, so check 65 fires WARN"
disable-model-invocation: true
disable-model-invocation-reason: test fixture only
---

# Fake New Carrier

Fixture body. Simulates an 11th disable-model-invocation carrier added after
checks 36/40/45/58-64 were written, with no dedicated check file naming its
path — check 65 should catch the coverage gap.
