#!/usr/bin/env python3
"""Self-check for the dangling-link did-you-mean suggestion. Run directly: python3 test_memory_lint.py"""
import importlib.util
import os
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
# SUT (memory-lint.py) stayed at skills/memory-lint/scripts/ per the no-move
# rule — Claude Code skill invocation contract relies on ${CLAUDE_SKILL_DIR}/scripts/.
# 3 levels up (tests/skills/memory-lint/ → repo root) then into the SUT dir.
spec = importlib.util.spec_from_file_location("memory_lint",
    os.path.join(HERE, "..", "..", "..", "skills", "memory-lint", "scripts", "memory-lint.py"))
assert spec and spec.loader
memory_lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(memory_lint)


def test_typo_link_gets_suggestion():
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "foo_bar.md"), "w") as f:
            f.write("---\nname: foo-bar\n---\nsome memory content\n")
        with open(os.path.join(d, "baz.md"), "w") as f:
            f.write("---\nname: baz\n---\nlinks to [[foo_br]]\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [baz](baz.md) — x\n- [foo_bar](foo_bar.md) — y\n")
        state = memory_lint.collect_state(d)
        findings, _, _ = memory_lint.detector_findings(state)
        dangling = [f for f in findings if "DANGLING" in f and "foo_br" in f]
        assert len(dangling) == 1, f"expected exactly one dangling finding for foo_br, got {dangling}"
        assert "did you mean [[foo_bar]]?" in dangling[0], f"expected suggestion, got: {dangling[0]}"


def test_unrelated_dangling_link_gets_no_suggestion():
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "foo_bar.md"), "w") as f:
            f.write("---\nname: foo-bar\n---\nsome memory content\n")
        with open(os.path.join(d, "baz.md"), "w") as f:
            f.write("---\nname: baz\n---\nlinks to [[completely_unrelated_topic_xyz]]\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [baz](baz.md) — x\n- [foo_bar](foo_bar.md) — y\n")
        state = memory_lint.collect_state(d)
        findings, _, _ = memory_lint.detector_findings(state)
        dangling = [f for f in findings if "DANGLING" in f and "completely_unrelated_topic_xyz" in f]
        assert len(dangling) == 1
        assert "did you mean" not in dangling[0], f"expected no suggestion, got: {dangling[0]}"


def _write_memory(d, filename, type_, description, body):
    with open(os.path.join(d, filename), "w") as f:
        f.write(f'---\nname: {filename[:-3]}\ndescription: "{description}"\n'
                 f"metadata:\n  type: {type_}\n---\n{body}\n")


def test_template_compliance_flags_feedback_memory_missing_both_fields():
    with tempfile.TemporaryDirectory() as d:
        _write_memory(d, "no-template.md", "feedback", "a lesson",
                       "just a rule, no Why or How")
        _write_memory(d, "full-template.md", "feedback", "another lesson",
                       "a rule\n\n**Why:** because\n\n**How to apply:** do the thing")
        # A reference-typed memory should never count toward the scoped total —
        # the template contract only applies to feedback/project.
        _write_memory(d, "a-reference.md", "reference", "not scoped", "n/a")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [no-template](no-template.md) — x\n"
                     "- [full-template](full-template.md) — y\n"
                     "- [a-reference](a-reference.md) — z\n")
        state = memory_lint.collect_state(d)
        result = memory_lint.template_compliance_findings(state)
        assert result["scoped_total"] == 2, f"reference-typed memory leaked into scoped_total: {result}"
        assert result["missing_why"] == 1
        assert result["missing_how"] == 1
        assert result["missing_both"] == ["no-template.md"]


def test_contradiction_candidates_requires_matching_type():
    with tempfile.TemporaryDirectory() as d:
        # High filename/description overlap but different types — must not pair.
        _write_memory(d, "deploy-via-actions.md", "feedback",
                       "user deploys via github actions never manually", "rule")
        _write_memory(d, "deploy-via-actions-note.md", "project",
                       "user deploys via github actions never manually", "note")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [deploy-via-actions](deploy-via-actions.md) — x\n"
                     "- [deploy-via-actions-note](deploy-via-actions-note.md) — y\n")
        state = memory_lint.collect_state(d)
        candidates = memory_lint.contradiction_candidates(state, min_overlap=0.35)
        assert candidates == [], f"expected no candidates across mismatched types, got {candidates}"


def test_contradiction_candidates_pairs_high_overlap_same_type():
    with tempfile.TemporaryDirectory() as d:
        _write_memory(d, "deploy-via-actions.md", "feedback",
                       "user deploys via github actions never manually by hand", "rule one")
        _write_memory(d, "deploy-process-notes.md", "feedback",
                       "user deploys via github actions never manually by hand", "rule two")
        _write_memory(d, "totally-unrelated.md", "feedback",
                       "completely different subject about database indexing", "rule three")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [deploy-via-actions](deploy-via-actions.md) — x\n"
                     "- [deploy-process-notes](deploy-process-notes.md) — y\n"
                     "- [totally-unrelated](totally-unrelated.md) — z\n")
        state = memory_lint.collect_state(d)
        candidates = memory_lint.contradiction_candidates(state, min_overlap=0.35)
        pairs = {frozenset((c["a"], c["b"])) for c in candidates}
        assert frozenset(("deploy-via-actions.md", "deploy-process-notes.md")) in pairs, candidates
        assert not any("totally-unrelated.md" in c["a"] or "totally-unrelated.md" in c["b"]
                        for c in candidates), candidates


def test_contradiction_candidates_shared_link_is_context_not_an_independent_trigger():
    # Regression test for the 2026-08-07 live-store hand-run: a shared outbound
    # [[link]] alone (both memories citing one common, unrelated prior finding)
    # must NOT be enough to surface a pair — only token-overlap crossing the
    # threshold does. The first version of this function used shared_links as
    # an independent OR trigger and produced 296 near-useless candidates on
    # the real 178-file store; token-overlap alone gave 4.
    with tempfile.TemporaryDirectory() as d:
        _write_memory(d, "topic-a.md", "project", "completely unrelated subject alpha",
                       "see [[shared-reference]]")
        _write_memory(d, "topic-b.md", "project", "totally different subject beta",
                       "also see [[shared-reference]]")
        _write_memory(d, "shared-reference.md", "project", "a commonly cited finding", "n/a")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [topic-a](topic-a.md) — x\n- [topic-b](topic-b.md) — y\n"
                     "- [shared-reference](shared-reference.md) — z\n")
        state = memory_lint.collect_state(d)
        candidates = memory_lint.contradiction_candidates(state, min_overlap=0.35)
        pair = {frozenset((c["a"], c["b"])) for c in candidates}
        assert frozenset(("topic-a.md", "topic-b.md")) not in pair, (
            f"a shared link alone must not surface a pair with near-zero token overlap: {candidates}")


if __name__ == "__main__":
    test_typo_link_gets_suggestion()
    test_unrelated_dangling_link_gets_no_suggestion()
    test_template_compliance_flags_feedback_memory_missing_both_fields()
    test_contradiction_candidates_requires_matching_type()
    test_contradiction_candidates_pairs_high_overlap_same_type()
    test_contradiction_candidates_shared_link_is_context_not_an_independent_trigger()
    print("OK")
