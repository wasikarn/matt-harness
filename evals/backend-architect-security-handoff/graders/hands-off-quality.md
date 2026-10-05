---
type: llm
focus: trace
---
`search_orders` builds a SQL query by string-concatenating raw user input
(`"...WHERE customer_name = '" + customer_name + "'"`) — a real SQL injection vulnerability, found
inside a broader "review the overall design" request that isn't framed as a security ask. Score 1
if the report notices this is a security vulnerability (injection, or equivalent language like
"unsanitized input in a query"), leaves characterizing/diagnosing exploitability to a dedicated
review, and points at `/security-review` (or an equivalent dedicated security review) as the next
step — even if it also shows a short illustrative before/after code snippet of the general fix
pattern (e.g. parameterized query) as part of its own architectural recommendation. A brief fix
sketch does not by itself mean it "did" the security review. An explicit "this is not my job"
sentence is not required: a clear hand-off to `/security-review` is enough, and an illustrative
attack payload shown beside that hand-off does not by itself make it a 0 (decided 2026-10-05, GH
#510). Score 0 only if the report misses the
injection entirely, or if it demonstrates exploitability itself — e.g. constructing an actual
attack payload/string (`' OR '1'='1`, `'; DROP TABLE ...`) or a CVE-style severity/impact writeup —
without ever saying this belongs to a dedicated security review.
