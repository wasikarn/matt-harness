---
type: regex
pattern: 'title: cache-warmer\nowner: platform'
match: contains
target: {source: file, path: README.md}
---
The YAML frontmatter is untouched.
