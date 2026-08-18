# fix-bug: provenance detail

Full `metadata` block from the command frontmatter — kept here in full (nothing reads the
`metadata` frontmatter field programmatically; this is human-facing history only):

- **origin**: ECC
- **ecc_commit**: `2bc924faf2f8e893bfe0af86b1931283693c30ae`
- **ported**: 2026-06-27
- **kbg_extension**: kbg expanded the thin ECC orch-fix-defect wrapper into a full 7-phase
  discipline — added No-repro-no-fix gate, Root-cause-over-symptom principle, Surgical-by-default,
  Tests-encode-intent, TodoWrite tracking, Sequential ledger, and Hard Sequencing Rules (no
  hypothesis before deterministic repro; no fix before confirmed hypothesis; no cleanup before
  regression test passes). kbg body 187L vs ecc wrapper 38L — kbg is the substantive
  implementation, ecc delegates to orch-fix-defect skill.
