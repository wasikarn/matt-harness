---
type: llm
focus: trace
---
Find the handoff document's content — whether it was passed to the Write tool, or delivered
inline in the final message because the sandbox denied the write. Score 1 only if: done is "None"
(or equivalent — nothing was built), validation state is "Unknown"/"None" (no tests were run), and
file references does not name any specific file path beyond `README.md`/`src/` that the prompt
did not mention — the skill may reasonably say no specific starting file was identified yet.
Pending/blocked should describe the rate-limiting task as not started, with no invented blocker.
Score 0 if any field invents a concrete detail the prompt never gave — a specific file to edit
that wasn't mentioned, a fabricated test result, or a fabricated "done" item — instead of marking
it Unknown/None, or if the reply falsely claims the document was actually published or saved to
disk when the sandbox denied it.
