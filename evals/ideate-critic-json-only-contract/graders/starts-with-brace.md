---
type: regex
target: last_message
match: contains
pattern: "^\\s*\\{"
---
The final relayed message starts with `{` (allowing only leading whitespace) — no narration like
"Here's the critic's output:" prepended before the JSON object.
