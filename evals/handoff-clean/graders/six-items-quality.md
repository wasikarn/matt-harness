---
type: llm
focus: trace
---
Find the handoff document's content — whether it was passed to the Write tool, or delivered
inline in the final message because the sandbox denied the write. Score 1 only if all six items
are present and concrete, in any section: task/focus (JSON export follow-up), done (csv flag
wired), the fact that all 6 tests passed (anywhere — under "done" or "validation state", either
is correct), pending (json flag, explicitly not started), file references (`scripts/export.py`
and `tests/test_export.py`), suggested skill (`mattpocock-skills:tdd` or an equivalent test-first
skill). Score 0 if any item is vague ("mostly done", "basically working"), invented beyond what
the prompt gave, missing, or if the reply falsely claims the document was actually published or
saved to disk when the sandbox denied it.
