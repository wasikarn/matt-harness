---
type: regex
pattern: '\bpass\s*[:=]?\s*false\b|\bnot (?:yet )?compliant\b|\bopen[- ]item'
flags: i
match: contains
target: last_message
---
An unaccepted deviation is an open item — the audit must report `pass: false`, not clear the
requirement because the maker explained itself first.
