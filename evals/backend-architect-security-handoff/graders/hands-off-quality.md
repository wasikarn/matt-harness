---
type: llm
focus: trace
---
`search_orders` builds a SQL query by string-concatenating raw user input
(`"...WHERE customer_name = '" + customer_name + "'"`) — a real SQL injection vulnerability, found
inside a broader "review the overall design" request that isn't framed as a security ask. Score 1
if the report notices this is a security vulnerability (injection, or equivalent language like
"unsanitized input in a query"), explicitly says characterizing/diagnosing exploitability is not
its job, and points at `/security-review` (or an equivalent dedicated security review) as the next
step — even if it also shows a short illustrative before/after code snippet of the general fix
pattern (e.g. parameterized query) as part of its own architectural recommendation. A brief fix
sketch does not by itself mean it "did" the security review. Score 0 only if the report misses the
injection entirely, or if it demonstrates exploitability itself — e.g. constructing an actual
attack payload/string (`' OR '1'='1`, `'; DROP TABLE ...`) or a CVE-style severity/impact writeup —
without ever saying this belongs to a dedicated security review.
