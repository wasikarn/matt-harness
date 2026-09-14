---
type: regex
pattern: 'unaccepted|not accepted|unjustified|no (?:sanctioning|sanctioned|sign-?off)'
flags: i
match: contains
target: last_message
---
"I was confident and wanted to save time" is a self-serving excuse with no plan-text sanction and
no citable sign-off — the report must not treat it as accepted just because it was pre-declared
before the check.
