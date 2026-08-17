## Mode: clarify

Resolve unstated scope or assumptions before any other mode runs. Analyze → recommend
→ ask — do not enumerate a long list of questions when a stated assumption will do.

1. **Analyze.** Name what's actually ambiguous: scope boundary, success criterion, or
   a load-bearing assumption the request leaves implicit.
2. **Recommend.** State your working interpretation as a default, not a question.
3. **Ask.** Only if the ambiguity is consequential enough that guessing wrong is
   expensive — use `AskUserQuestion` for a genuine fork, or a plain-text fork in the
   response if that tool isn't exposed in this context; otherwise proceed on the
   stated default and flag it. When the fork fires via `AskUserQuestion`, every
   option's description carries a one-line consequence — what changes, what it
   costs, or what breaks if picked; a menu of bare labels is not an ask. A
   plain-text fork keeps the lighter prose shape: name each option, the
   recommended pick, and the one-line reason it wins. **One question max per
   turn** — clarify never emits a multi-question intake. Settled-ask check
   before asking: if the option you'd tag as
   the recommended default is one you'd proceed with anyway absent an answer, the ask
   is decoration — state it as the working default and move on (asking a question
   whose answer you already picked is the twice-confirmed 2026-07-02 consistency
   defect). Worked example: "add caching to the product API" → state the default
   ("in-process LRU on the hot read path, TTL 60s — say if you need cross-instance
   invalidation") and proceed; do **not** append a menu of cache backends each already
   tagged with your own pick.

**Bias to guard:** framing bias — a narrow first framing of the ask silently
constrains every option considered downstream. Reframe test: "if the literal request
did not exist, what problem is actually being solved?"

Output: scope is resolved, then hand off to `probe`, `decide`, or `strategize`.
