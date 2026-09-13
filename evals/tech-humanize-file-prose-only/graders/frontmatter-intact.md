---
type: regex
pattern: '-{3}\ntitle: cache-warmer\nowner: platform\n-{3}'
match: contains
target: {source: file, path: README.md}
---
The YAML frontmatter is untouched: both delimiter lines and both field values survive exactly.
`-{3}` stands in for the YAML delimiter line (three dashes) — a literal run of three dashes
inside this grader's own frontmatter previously broke the CLI's frontmatter-boundary scan for
this same file, so the pattern above spells it as a regex quantifier instead of the raw
character sequence. The earlier looser version dropped the delimiter check entirely and had no
end-anchor on the owner field, so it silently passed a file with the delimiter lines deleted, or
the owner value changed to `platform-other`.
