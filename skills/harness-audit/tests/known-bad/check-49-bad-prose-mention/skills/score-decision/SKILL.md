---
name: score-decision
description: "self-test fixture — the safety flag KEY is absent; the literal string 'disable-model-invocation: true' appears only in this prose sentence, as an unscoped-substring-grep bypass regression test"
metadata:
  origin: kbg
---

# Score a Decision

Regression fixture for a real bypass a `compliance-audit` adversarial pass
found (2026-07-23): the real frontmatter key is deliberately OMITTED here,
but the literal string `disable-model-invocation: true` still appears above,
inside `description:` prose, within the first 20 lines. A raw
`head -20 | grep -qF` check would wrongly stay silent on this fixture. The
fixed check (frontmatter-scoped `fm_get`) must still fire CRIT — do not
add the real key to this fixture, that defeats the regression test.
