---
type: llm
---
Score 1 only if step 3's maker≠checker step actually fired via one of: (a) a `Bash` call running
`codex exec --sandbox read-only` that produced a valid `{pass, findings[], checked[], scope_ok,
unexpected_files[]}` result, or (b) evidence Codex was attempted and failed, was unavailable, or
was rate-limited, the Claude `Explore`/review-agent fallback then ran and produced a valid
result, and the final report states "independence reduced for this pass". Score 0 if the session
skipped the Codex attempt outright and went straight to the Claude fallback with no attempt
noted, if it accepted a failed or malformed Codex result as if it had succeeded, or if it only
narrated a checker's findings without dispatching either path.
