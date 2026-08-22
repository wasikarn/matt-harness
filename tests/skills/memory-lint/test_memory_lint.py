#!/usr/bin/env python3
"""Self-check for the dangling-link did-you-mean suggestion. Run directly: python3 test_memory_lint.py"""
import importlib.util
import json
import os
import subprocess
import tempfile
import time

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
        findings, _, _, _ = memory_lint.detector_findings(state)
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
        findings, _, _, _ = memory_lint.detector_findings(state)
        dangling = [f for f in findings if "DANGLING" in f and "completely_unrelated_topic_xyz" in f]
        assert len(dangling) == 1
        assert "did you mean" not in dangling[0], f"expected no suggestion, got: {dangling[0]}"


def test_markdown_style_dangling_link_is_detected():
    # Regression test for the 2026-08-07 gap: DANGLING used to only scan
    # [[wikilinks]], so a same-store markdown-style [text](file.md) link to a
    # nonexistent memory was invisible to the detector.
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "baz.md"), "w") as f:
            f.write("---\nname: baz\n---\nsee [ghost](ghost-topic.md) for detail\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [baz](baz.md) — x\n")
        state = memory_lint.collect_state(d)
        findings, _, _, _ = memory_lint.detector_findings(state)
        dangling = [f for f in findings if "DANGLING" in f and "ghost-topic" in f]
        assert len(dangling) == 1, f"expected a dangling finding for the markdown-style link, got {findings}"


def test_markdown_style_link_in_backticks_is_not_a_real_reference():
    # Regression test: prose can quote link syntax as an example of a bug found
    # in another repo (confirmed live in plugin-install-portability.md, which
    # cites `[reference.md](reference.md)` as a fixed-elsewhere example). That
    # must not be treated as a same-store cross-link.
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "baz.md"), "w") as f:
            f.write("---\nname: baz\n---\nsaw `[reference.md](reference.md)` used elsewhere\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [baz](baz.md) — x\n")
        state = memory_lint.collect_state(d)
        findings, _, _, _ = memory_lint.detector_findings(state)
        assert not any("reference" in f for f in findings), (
            f"backtick-quoted link syntax must not be scanned as a real reference: {findings}")


def test_markdown_style_link_with_path_is_treated_as_external_not_dangling():
    # This store's memories live flat (no subdirectories except _archive/), so
    # a target containing "/" is a citation into another repo, not a same-store
    # link — confirmed live in plugin-install-portability.md's
    # ../../docs/reference/reasoning-models.md citation.
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "baz.md"), "w") as f:
            f.write("---\nname: baz\n---\nsee [x](../../docs/reference/reasoning-models.md)\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [baz](baz.md) — x\n")
        state = memory_lint.collect_state(d)
        findings, _, _, _ = memory_lint.detector_findings(state)
        assert not any("reasoning-models" in f for f in findings), (
            f"a path-qualified markdown target must not be scanned as a same-store link: {findings}")


def test_markdown_style_link_to_real_memory_resolves_and_avoids_false_orphan():
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "foo_bar.md"), "w") as f:
            f.write("---\nname: foo-bar\n---\nsome memory content\n")
        with open(os.path.join(d, "baz.md"), "w") as f:
            f.write("---\nname: baz\n---\nsee [foo bar](foo_bar.md) for detail\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [baz](baz.md) — x\n- [foo_bar](foo_bar.md) — y\n")
        state = memory_lint.collect_state(d)
        findings, _, _, _ = memory_lint.detector_findings(state)
        assert not any("DANGLING" in f or "ORPHAN" in f for f in findings), findings


def test_class_d_count_fold_fires_over_trigger_and_reaches_target():
    # Regression test for the 2026-08-07 Class D addition: A/B/C only catch a
    # few verbose outliers or explicit **SUPERSEDED** markers, so a store made
    # of many small terse entries (this store's real shape) sails past 80% of
    # cap with 0 candidates from either class — confirmed live against the
    # real pre-trim MEMORY.md (21,632B/84%, A and B both found 0). Class D is
    # the fallback valve for exactly that shape.
    orig_line_cap, orig_byte_cap = memory_lint.LINE_CAP, memory_lint.BYTE_CAP
    try:
        memory_lint.LINE_CAP = 10_000  # keep line-cap out of the way; test byte-cap only
        memory_lint.BYTE_CAP = 480
        with tempfile.TemporaryDirectory() as d:
            idx_lines = []
            now = 2_000_000_000
            for i in range(6):
                stem = f"topic-{i}"
                with open(os.path.join(d, f"{stem}.md"), "w") as f:
                    f.write(f"---\nname: {stem}\n---\nsome memory content about topic {i}\n")
                os.utime(os.path.join(d, f"{stem}.md"), (now + i * 100, now + i * 100))
                idx_lines.append(f"- [{stem}]({stem}.md) — a short pointer hook for topic {i} here")
            with open(os.path.join(d, "MEMORY.md"), "w") as f:
                f.write("\n".join(idx_lines) + "\n")
            state = memory_lint.collect_state(d)
            idx_bytes = len(state["idx"].encode("utf-8"))
            assert idx_bytes / memory_lint.BYTE_CAP >= 0.80, "fixture must actually cross the trigger"

            plan = memory_lint.class_d_count_fold(state, exclude_files=set())
            assert plan, "expected Class D to propose at least one deindex above the trigger"
            # Oldest-mtime-first: topic-0 (lowest mtime) must be folded before topic-5 (highest).
            folded = [e["file"] for e in plan]
            assert folded[0] == "topic-0.md", f"expected oldest-mtime file first, got {folded}"
            assert "topic-5.md" not in folded or folded.index("topic-5.md") == len(folded) - 1, (
                f"newest-mtime file should be folded last if at all: {folded}")

            freed = sum(len(e["old_pointer_line"].encode("utf-8")) + 1 for e in plan)
            remaining = idx_bytes - freed
            target = memory_lint.BYTE_CAP * memory_lint.FOLD_TARGET_PCT
            assert remaining <= target, (
                f"Class D plan must actually reach target: {remaining}B remaining vs {target}B target")
    finally:
        memory_lint.LINE_CAP, memory_lint.BYTE_CAP = orig_line_cap, orig_byte_cap


def test_class_d_count_fold_returns_nothing_under_trigger():
    orig_byte_cap = memory_lint.BYTE_CAP
    try:
        memory_lint.BYTE_CAP = 1_000_000  # index nowhere near this cap
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "topic.md"), "w") as f:
                f.write("---\nname: topic\n---\nsome memory content\n")
            with open(os.path.join(d, "MEMORY.md"), "w") as f:
                f.write("- [topic](topic.md) — a short pointer hook\n")
            state = memory_lint.collect_state(d)
            plan = memory_lint.class_d_count_fold(state, exclude_files=set())
            assert plan == [], f"expected no Class D candidates well under trigger, got {plan}"
    finally:
        memory_lint.BYTE_CAP = orig_byte_cap


def _write_memory(d, filename, type_, description, body):
    with open(os.path.join(d, filename), "w") as f:
        f.write(f'---\nname: {filename[:-3]}\ndescription: "{description}"\n'
                 f"metadata:\n  type: {type_}\n---\n{body}\n")


def _git(d, *args):
    subprocess.run(["git", "-C", d, *args], check=True, capture_output=True, text=True)


def _init_git_repo(d):
    # Deterministic, non-interactive commits for a disposable test fixture repo —
    # unrelated to the "don't bypass the user's real signing policy" rule, which
    # governs this repo's own history, not a temp dir created and discarded by a test.
    _git(d, "init", "-q")
    _git(d, "config", "user.email", "test@example.com")
    _git(d, "config", "user.name", "Test")
    _git(d, "config", "commit.gpgsign", "false")


def _git_commit(d, message):
    _git(d, "add", "-A")
    _git(d, "commit", "-q", "-m", message)


def test_template_compliance_flags_feedback_memory_missing_both_fields():
    with tempfile.TemporaryDirectory() as d:
        _write_memory(d, "no-template.md", "feedback", "a lesson",
                       "just a rule, no Why or How")
        _write_memory(d, "full-template.md", "feedback", "another lesson",
                       "a rule\n\n**Why:** because\n\n**How to apply:** do the thing")
        # A second BOTH-present memory makes the fixture asymmetric: without it,
        # present-count == missing-count == 1, so `if not has_why` / `if not has_how`
        # (L452/L454) score identically to their inverted mutants. With it,
        # present=2 vs missing=1, so the inversion flips the counts.
        _write_memory(d, "also-full.md", "feedback", "third lesson",
                       "a rule\n\n**Why:** cuz\n\n**How to apply:** do it")
        # A reference-typed memory should never count toward the scoped total —
        # the template contract only applies to feedback/project.
        _write_memory(d, "a-reference.md", "reference", "not scoped", "n/a")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [no-template](no-template.md) — x\n"
                     "- [full-template](full-template.md) — y\n"
                     "- [also-full](also-full.md) — w\n"
                     "- [a-reference](a-reference.md) — z\n")
        state = memory_lint.collect_state(d)
        result = memory_lint.template_compliance_findings(state)
        assert result["scoped_total"] == 3, f"reference-typed memory leaked into scoped_total: {result}"
        # Asymmetric fixture (2 with each field, 1 without) makes these load-bearing:
        # the inverted-condition mutants would report 2, not 1.
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


def test_classify_unindexed_confirms_git_fold():
    # Regression fixture for the corrected Adopt-1 design (see
    # docs/research/claude-mem-architecture-study-2026-08-07.md): a file that
    # WAS pointed to and got deliberately removed by a fold commit must be
    # classified folded-confirmed, never treated as a candidate to re-add.
    with tempfile.TemporaryDirectory() as d:
        _init_git_repo(d)
        _write_memory(d, "folded-target.md", "project", "a finished audit", "n/a")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [folded-target](folded-target.md) — a finished audit\n")
        _git_commit(d, "add folded-target pointer")

        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("")  # fold: pointer removed, backing file kept
        _git_commit(d, "fold rule: drop stale index entry")

        state = memory_lint.collect_state(d)
        results = memory_lint.classify_unindexed(state)
        match = [r for r in results if r["file"] == "folded-target.md"]
        assert len(match) == 1, results
        assert match[0]["bucket"] == "folded-confirmed", match[0]
        assert match[0]["commit"] and match[0]["commit"]["sha"], match[0]


def test_classify_unindexed_flags_never_indexed_after_baseline():
    with tempfile.TemporaryDirectory() as d:
        _init_git_repo(d)
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("")  # baseline commit predates the target file entirely
        _git_commit(d, "baseline")

        _write_memory(d, "new-target.md", "project", "written after baseline", "n/a")

        state = memory_lint.collect_state(d)
        results = memory_lint.classify_unindexed(state)
        match = [r for r in results if r["file"] == "new-target.md"]
        assert len(match) == 1, results
        assert match[0]["bucket"] == "never-indexed", match[0]
        assert match[0]["commit"] is None


def test_classify_unindexed_flags_ambiguous_when_pre_baseline():
    with tempfile.TemporaryDirectory() as d:
        _write_memory(d, "old-target.md", "project", "written before the repo existed", "n/a")

        _init_git_repo(d)
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("")
        _git_commit(d, "baseline")  # baseline snapshot includes old-target.md

        state = memory_lint.collect_state(d)
        results = memory_lint.classify_unindexed(state)
        match = [r for r in results if r["file"] == "old-target.md"]
        assert len(match) == 1, results
        assert match[0]["bucket"] == "ambiguous-pre-baseline", match[0]


def test_classify_unindexed_pre_baseline_file_edited_later_stays_ambiguous():
    # Regression test for a bug caught by advisor() before shipping: an
    # mtime-based check (mtime >= baseline_epoch) would misclassify a
    # pre-baseline file as never-indexed the first time anyone edits it after
    # tracking starts, since mtime resets on every save. Tree membership at
    # the baseline commit is the correct signal — it's a fixed fact about
    # history, immune to later edits.
    with tempfile.TemporaryDirectory() as d:
        _write_memory(d, "old-but-edited.md", "project", "existed before tracking started", "n/a")

        _init_git_repo(d)
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("")
        _git_commit(d, "baseline")  # baseline snapshot includes old-but-edited.md

        future = time.time() + 10_000
        os.utime(os.path.join(d, "old-but-edited.md"), (future, future))

        state = memory_lint.collect_state(d)
        results = memory_lint.classify_unindexed(state)
        match = [r for r in results if r["file"] == "old-but-edited.md"]
        assert len(match) == 1, results
        assert match[0]["bucket"] == "ambiguous-pre-baseline", match[0]


def test_classify_unindexed_handles_no_git_repo():
    with tempfile.TemporaryDirectory() as d:
        _write_memory(d, "plain-target.md", "project", "no git here", "n/a")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("")
        state = memory_lint.collect_state(d)
        results = memory_lint.classify_unindexed(state)
        match = [r for r in results if r["file"] == "plain-target.md"]
        assert len(match) == 1, results
        assert match[0]["bucket"] == "no-git-history", match[0]


def test_classify_unindexed_no_substring_collision():
    # Regression test for a HIGH finding from this session's adversarial
    # review: the old `git log -S<filename>` search matched filename as a
    # SUBSTRING anywhere in MEMORY.md's diff text, so a never-indexed file
    # whose name happens to be a substring of a genuinely-folded file's name
    # (review.md vs code-review.md) got misclassified as folded-confirmed.
    with tempfile.TemporaryDirectory() as d:
        _init_git_repo(d)
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("")
        _git_commit(d, "baseline (neither file exists yet)")

        _write_memory(d, "code-review.md", "project", "the long filename", "n/a")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [code-review](code-review.md) — the long filename\n")
        _git_commit(d, "index code-review")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("")
        _git_commit(d, "fold rule: drop code-review pointer")

        _write_memory(d, "review.md", "project",
                       "short name, substring of code-review.md, never referenced at all", "n/a")

        state = memory_lint.collect_state(d)
        results = memory_lint.classify_unindexed(state)
        match = [r for r in results if r["file"] == "review.md"]
        assert len(match) == 1, results
        assert match[0]["bucket"] == "never-indexed", (
            f"review.md was never a real link, must not inherit code-review.md's fold: {match[0]}")


def test_classify_unindexed_no_prose_mention_false_fold():
    # Regression test for a HIGH finding from this session's adversarial
    # review (blind-spot-hunter): a filename mentioned only in PROSE (never
    # wrapped in a real [text](file.md) link) must not be credited as folded
    # just because that prose sentence gets edited later for unrelated
    # reasons — mentioned.md was never actually indexed.
    with tempfile.TemporaryDirectory() as d:
        _init_git_repo(d)
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("")
        _git_commit(d, "baseline (neither file exists yet)")

        _write_memory(d, "other.md", "project", "the real entry", "n/a")
        _write_memory(d, "mentioned.md", "project", "never linked, only named in prose", "n/a")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [other](other.md) — see mentioned.md for background\n")
        _git_commit(d, "index other, mention mentioned.md in prose only")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [other](other.md) — background note\n")
        _git_commit(d, "trim prose (mentioned.md was never a real link)")

        state = memory_lint.collect_state(d)
        results = memory_lint.classify_unindexed(state)
        match = [r for r in results if r["file"] == "mentioned.md"]
        assert len(match) == 1, results
        assert match[0]["bucket"] == "never-indexed", (
            f"a bare prose mention must not be credited as a real fold: {match[0]}")


def test_classify_unindexed_failed_git_query_is_safe_not_never_indexed():
    # Regression test for a HIGH finding from this session's adversarial
    # review (silent-failure-hunter): the old per-file design caught a git
    # subprocess failure and silently fell through to the confident
    # never-indexed bucket — the wrong direction, since it could relabel a
    # genuinely-folded file as a fresh candidate to re-add. A failed git
    # query must land in its own distinct bucket instead.
    with tempfile.TemporaryDirectory() as d:
        _init_git_repo(d)
        _write_memory(d, "folded-file.md", "project", "will be folded", "n/a")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [folded-file](folded-file.md) — will be folded\n")
        _git_commit(d, "index folded-file")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("")
        _git_commit(d, "fold rule: drop folded-file pointer")

        state = memory_lint.collect_state(d)
        orig = memory_lint._git_fold_commits
        memory_lint._git_fold_commits = lambda d: ({}, False)  # simulate a failed git call
        try:
            results = memory_lint.classify_unindexed(state)
        finally:
            memory_lint._git_fold_commits = orig

        match = [r for r in results if r["file"] == "folded-file.md"]
        assert len(match) == 1, results
        assert match[0]["bucket"] == "git-query-failed", (
            f"a failed fold-detection call must not silently become never-indexed: {match[0]}")


def test_classify_unindexed_git_call_count_stays_constant_regardless_of_file_count():
    # Regression test for the 2026-08-07 O(N)-subprocess redesign: the actual
    # defect (~744ms against the real 178-file store, ~356ms at a synthetic
    # N=30) was subprocess-SPAWN COUNT scaling with the number of UNINDEXED
    # files, not any one call being slow. A wall-clock assertion would be
    # flaky on a loaded machine; the call count is the real invariant and
    # fails deterministically if someone reverts to a per-file loop.
    with tempfile.TemporaryDirectory() as d:
        _init_git_repo(d)
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("")
        _git_commit(d, "baseline")
        for i in range(5):
            _write_memory(d, f"topic-{i}.md", "project", f"fixture {i}", "n/a")

        state = memory_lint.collect_state(d)
        calls = []
        orig_run = memory_lint.subprocess.run

        def counting_run(*args, **kwargs):
            calls.append(args[0] if args else kwargs.get("args"))
            return orig_run(*args, **kwargs)

        memory_lint.subprocess.run = counting_run
        try:
            results = memory_lint.classify_unindexed(state)
        finally:
            memory_lint.subprocess.run = orig_run

        git_calls = [c for c in calls if c and c[0] == "git"]
        assert len(git_calls) == 3, (
            f"expected exactly 3 git calls (first-commit + fold-scan + baseline-tree) "
            f"regardless of file count, got {len(git_calls)}: {git_calls}")
        assert len(results) == 5


def test_unindexed_file_linked_from_indexed_memory_is_context_layer_not_a_finding():
    """Fold rule Layer-2: unindexed but [[link]]-reachable from an indexed root
    must NOT fire UNINDEXED — it's counted in context_layer instead."""
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "hub.md"), "w") as f:
            f.write("---\nname: hub\n---\nindexed hub, links [[ctx_note]]\n")
        with open(os.path.join(d, "ctx_note.md"), "w") as f:
            f.write("---\nname: ctx-note\n---\ncontext-layer detail, no index line\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [hub](hub.md) — the indexed root\n")
        state = memory_lint.collect_state(d)
        findings, _, _, context_layer = memory_lint.detector_findings(state)
        unindexed = [x for x in findings if "UNINDEXED" in x]
        assert unindexed == [], f"linked context file must not fire UNINDEXED, got {unindexed}"
        assert context_layer == 1, f"expected context_layer == 1, got {context_layer}"


def test_unindexed_and_unreachable_file_still_fires_unindexed():
    """A file with no index pointer and no inbound path from the index is real
    rot and must still fire exactly one UNINDEXED finding naming it."""
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "hub.md"), "w") as f:
            f.write("---\nname: hub\n---\nindexed, links nothing\n")
        with open(os.path.join(d, "stray.md"), "w") as f:
            f.write("---\nname: stray\n---\nnobody points here\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [hub](hub.md) — the indexed root\n")
        state = memory_lint.collect_state(d)
        findings, _, _, context_layer = memory_lint.detector_findings(state)
        unindexed = [x for x in findings if x.startswith("UNINDEXED: stray.md")]
        assert len(unindexed) == 1, f"expected exactly one UNINDEXED for stray.md, got {findings}"
        assert context_layer == 0, f"unreachable file must not count as context-layer, got {context_layer}"


def test_context_layer_reachability_is_transitive_through_unindexed_files():
    """Index -> hub -> [[mid]] -> [[leaf]]: mid and leaf are both unindexed but
    reachable through the chain, so neither fires and context_layer == 2."""
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "hub.md"), "w") as f:
            f.write("---\nname: hub\n---\nlinks [[mid]]\n")
        with open(os.path.join(d, "mid.md"), "w") as f:
            f.write("---\nname: mid\n---\nlinks onward to [[leaf]]\n")
        with open(os.path.join(d, "leaf.md"), "w") as f:
            f.write("---\nname: leaf\n---\nend of the chain\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [hub](hub.md) — the indexed root\n")
        state = memory_lint.collect_state(d)
        findings, _, _, context_layer = memory_lint.detector_findings(state)
        unindexed = [x for x in findings if "UNINDEXED" in x]
        assert unindexed == [], f"transitively reachable files must not fire, got {unindexed}"
        assert context_layer == 2, f"expected context_layer == 2 (mid+leaf), got {context_layer}"


def test_find_patterns_clusters_by_shared_link():
    """--find-patterns groups memories into connected components by shared
    resolvable [[link]] referents. A/B/C all link [[hub]] so they form one
    cluster of size 3; D links only [[other]] so it stays isolated. A dangling
    link (no resolvable target) must NOT seed an edge."""
    with tempfile.TemporaryDirectory() as d:
        for name in ("a", "b", "c"):
            with open(os.path.join(d, f"{name}.md"), "w") as f:
                f.write(f"---\nname: {name}\n---\nsee [[hub]] and a [[ghost]] that resolves nowhere\n")
        with open(os.path.join(d, "d.md"), "w") as f:
            f.write("---\nname: d\n---\nsee [[other]]\n")
        # resolvable targets so [[hub]]/[[other]] create edges (by filename stem)
        with open(os.path.join(d, "hub.md"), "w") as f:
            f.write("---\nname: hub\n---\nshared referent\n")
        with open(os.path.join(d, "other.md"), "w") as f:
            f.write("---\nname: other\n---\nother referent\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [a](a.md)\n- [b](b.md)\n- [c](c.md)\n- [d](d.md)\n- [hub](hub.md)\n- [other](other.md)\n")
        state = memory_lint.collect_state(d)

        # default min_cluster=3: exactly one cluster {a,b,c} bound by hub
        clusters = memory_lint.pattern_clusters(state, 3)
        assert len(clusters) == 1, f"expected 1 cluster at min_cluster=3, got {len(clusters)}: {clusters}"
        assert set(clusters[0]["members"]) == {"a.md", "b.md", "c.md"}, clusters[0]["members"]
        assert "hub" in clusters[0]["shared_links"], clusters[0]["shared_links"]
        # d.md must not appear (isolated, below threshold)
        assert "d.md" not in {m for c in clusters for m in c["members"]}, "d.md should be isolated"
        # the dangling [[ghost]] must not create an edge or a shared link
        assert "ghost" not in clusters[0]["shared_links"], "dangling link must not seed an edge"

        # mutation guard: drop [[hub]] from a.md -> {a} is now isolated,
        # {b,c} drops to size 2, so no cluster survives at min_cluster=3
        with open(os.path.join(d, "a.md"), "w") as f:
            f.write("---\nname: a\n---\nonly a [[ghost]] that resolves nowhere\n")
        state2 = memory_lint.collect_state(d)
        clusters2 = memory_lint.pattern_clusters(state2, 3)
        assert clusters2 == [], f"removing one hub link must dissolve the size-3 cluster, got {clusters2}"

        # --max-cluster caps component size: the {a,b,c} cluster (size 3) must be
        # hidden by max_cluster=2, leaving no clusters. Guards the dense-store
        # giant-component filter — raising min_cluster cannot remove the largest
        # component, only an upper bound can.
        with open(os.path.join(d, "a.md"), "w") as f:
            f.write("---\nname: a\n---\nsee [[hub]]\n")
        state3 = memory_lint.collect_state(d)
        capped = memory_lint.pattern_clusters(state3, 3, max_cluster=2)
        assert capped == [], f"max_cluster=2 must hide the size-3 cluster, got {capped}"
        # and it must NOT hide a cluster at or below the cap
        kept = memory_lint.pattern_clusters(state3, 3, max_cluster=3)
        assert len(kept) == 1 and kept[0]["size"] == 3, f"max_cluster=3 must keep the size-3 cluster, got {kept}"


def test_find_patterns_cli_default_caps_giant_component():
    """--max-cluster now defaults to 10 at the CLI layer (pattern_clusters()
    itself still defaults to 0/uncapped for direct callers). Regression test
    for the 2026-08-17 incident: a plain `--find-patterns` hand-run with no
    flag saw a giant component mixed in with the real small clusters and
    misdiagnosed the clustering algorithm as broken — the fix (--max-cluster)
    already existed but wasn't on by default. A size-12 hub-linked component
    must be excluded from output with zero extra flags; a size-3 tight
    cluster on a different hub must still surface."""
    with tempfile.TemporaryDirectory() as d:
        big_names = [f"big{i}" for i in range(12)]
        for name in big_names:
            with open(os.path.join(d, f"{name}.md"), "w") as f:
                f.write(f"---\nname: {name}\n---\nsee [[bighub]]\n")
        with open(os.path.join(d, "bighub.md"), "w") as f:
            f.write("---\nname: bighub\n---\nshared referent\n")
        for name in ("a", "b", "c"):
            with open(os.path.join(d, f"{name}.md"), "w") as f:
                f.write(f"---\nname: {name}\n---\nsee [[tighthub]]\n")
        with open(os.path.join(d, "tighthub.md"), "w") as f:
            f.write("---\nname: tighthub\n---\nshared referent\n")
        index_lines = [f"- [{n}]({n}.md)" for n in big_names + ["bighub", "a", "b", "c", "tighthub"]]
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("\n".join(index_lines) + "\n")

        script = os.path.join(os.path.dirname(__file__), "..", "..", "..",
                               "skills", "memory-lint", "scripts", "memory-lint.py")
        result = subprocess.run(
            ["python3", script, d, "--find-patterns"],
            capture_output=True, text=True, check=True,
        )
        assert "max-cluster: 10" in result.stdout, \
            f"CLI default must be 10, got: {result.stdout[:200]}"
        assert "clusters: 1" in result.stdout, \
            f"the size-12 hub component must be capped out, only the size-3 cluster should remain: {result.stdout}"
        assert "bighub" not in result.stdout, \
            f"the giant component must not appear in default output: {result.stdout}"
        assert "tighthub" in result.stdout, \
            f"the tight size-3 cluster must still surface by default: {result.stdout}"
        assert "1 above cap, hidden" in result.stdout, \
            f"the capped-out component must be counted, not silently dropped: {result.stdout}"


def test_find_patterns_reports_hidden_count_when_everything_is_capped_out():
    """When every component exceeds --max-cluster, the empty-result branch
    must say so, not claim no cluster reached --min-cluster (that claim
    would be false — a qualifying cluster exists, it's just hidden)."""
    with tempfile.TemporaryDirectory() as d:
        big_names = [f"big{i}" for i in range(12)]
        for name in big_names:
            with open(os.path.join(d, f"{name}.md"), "w") as f:
                f.write(f"---\nname: {name}\n---\nsee [[bighub]]\n")
        with open(os.path.join(d, "bighub.md"), "w") as f:
            f.write("---\nname: bighub\n---\nshared referent\n")
        index_lines = [f"- [{n}]({n}.md)" for n in big_names + ["bighub"]]
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("\n".join(index_lines) + "\n")

        script = os.path.join(os.path.dirname(__file__), "..", "..", "..",
                               "skills", "memory-lint", "scripts", "memory-lint.py")
        result = subprocess.run(
            ["python3", script, d, "--find-patterns"],
            capture_output=True, text=True, check=True,
        )
        assert "clusters: 0" in result.stdout, f"expected 0 clusters within the cap: {result.stdout}"
        assert "none within the cap" in result.stdout, \
            f"empty-result message must say a component was hidden, not that none reached --min-cluster: {result.stdout}"
        assert "no connected component reached" not in result.stdout, \
            f"this message is false when a component exists but is capped out: {result.stdout}"


def test_find_patterns_json_prompt_includes_prompts():
    """Regression test for a 2026-08-17 finding (kbg:bug-sweep): --json's
    early `return 0` used to fire before the --prompt block ever ran, so
    `--find-patterns --json --prompt` silently dropped the prompt content
    with no warning — byte-identical to `--json` alone. JSON must mirror
    text mode's --prompt output (run_detector() already sets this precedent
    for the stale/template_compliance fields), so a caller building
    automation around --json has a way to see --prompt actually fired."""
    with tempfile.TemporaryDirectory() as d:
        for name in ("a", "b", "c"):
            with open(os.path.join(d, f"{name}.md"), "w") as f:
                f.write(f"---\nname: {name}\n---\nsee [[tighthub]]\n")
        with open(os.path.join(d, "tighthub.md"), "w") as f:
            f.write("---\nname: tighthub\n---\nshared referent\n")
        index_lines = [f"- [{n}]({n}.md)" for n in ("a", "b", "c", "tighthub")]
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("\n".join(index_lines) + "\n")

        script = os.path.join(os.path.dirname(__file__), "..", "..", "..",
                               "skills", "memory-lint", "scripts", "memory-lint.py")
        with_prompt = subprocess.run(
            ["python3", script, d, "--find-patterns", "--json", "--prompt"],
            capture_output=True, text=True, check=True,
        )
        parsed = json.loads(with_prompt.stdout)
        assert "prompts" in parsed, f"--json --prompt must include a prompts key: {with_prompt.stdout}"
        assert len(parsed["prompts"]) == len(parsed["clusters"]) == 1, \
            f"expected exactly 1 prompt for the 1 qualifying cluster: {parsed}"
        assert "tighthub" in parsed["prompts"][0], f"prompt content missing shared-link context: {parsed['prompts'][0]}"

        without_prompt = subprocess.run(
            ["python3", script, d, "--find-patterns", "--json"],
            capture_output=True, text=True, check=True,
        )
        assert "prompts" not in json.loads(without_prompt.stdout), \
            "plain --json (no --prompt) must not include a prompts key"


def test_find_patterns_cli_boundary_at_exact_cap_size():
    """Regression test for a 2026-08-17 mutation-testing finding (kbg:bug-sweep):
    run_find_patterns()'s own re-filter (`c["size"] <= max_cluster`) had zero
    test coverage at size == max_cluster through the actual CLI path — a
    mutated `<=` -> `<` still passed the full suite. A cluster sized exactly
    at the cap must be KEPT, not hidden (the cap is inclusive, matching
    pattern_clusters()'s own `> max_cluster` exclusion boundary)."""
    with tempfile.TemporaryDirectory() as d:
        names = [f"m{i}" for i in range(5)]
        for name in names:
            with open(os.path.join(d, f"{name}.md"), "w") as f:
                f.write(f"---\nname: {name}\n---\nsee [[exacthub]]\n")
        with open(os.path.join(d, "exacthub.md"), "w") as f:
            f.write("---\nname: exacthub\n---\nshared referent\n")
        index_lines = [f"- [{n}]({n}.md)" for n in names + ["exacthub"]]
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("\n".join(index_lines) + "\n")

        script = os.path.join(os.path.dirname(__file__), "..", "..", "..",
                               "skills", "memory-lint", "scripts", "memory-lint.py")
        result = subprocess.run(
            ["python3", script, d, "--find-patterns", "--max-cluster", "5"],
            capture_output=True, text=True, check=True,
        )
        assert "clusters: 1" in result.stdout, \
            f"a cluster sized exactly at --max-cluster must be kept, not hidden: {result.stdout}"
        assert "0 above cap" not in result.stdout and "above cap, hidden" not in result.stdout, \
            f"nothing should be reported as hidden when the only cluster is exactly at the cap: {result.stdout}"
        assert "exacthub" in result.stdout, f"the size-5 cluster's content must appear: {result.stdout}"


def test_memory_dir_project_dir_name_requires_config_dir():
    """Regression test for a bug memory_dir() shipped and had to fix twice in
    one session: the round-1 fix honored CLAUDE_CODE_PROJECT_DIR_NAME whenever
    it was set, citing memory.md — which doesn't mention that Claude Code
    "ignores this variable when CLAUDE_CONFIG_DIR is unset" (env-vars.md:326).
    Round-2 fixed it but was verified only in an ad-hoc scratch dir, leaving
    no committed coverage to catch a future re-regression of the same bug."""
    with tempfile.TemporaryDirectory() as repo, tempfile.TemporaryDirectory() as cfg:
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "init"], cwd=repo, check=True)
        toplevel = subprocess.run(
            ["git", "-C", repo, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        git_enc = toplevel.replace("/", "-")

        saved_cwd = os.getcwd()
        saved_env = {k: os.environ.get(k) for k in ("CLAUDE_CONFIG_DIR", "CLAUDE_CODE_PROJECT_DIR_NAME")}
        try:
            os.chdir(repo)
            for k in saved_env:
                os.environ.pop(k, None)

            neither = memory_lint.memory_dir(None)
            assert neither == os.path.join(os.path.expanduser("~/.claude/projects"), git_enc, "memory"), neither

            os.environ["CLAUDE_CODE_PROJECT_DIR_NAME"] = "myrepo"
            dirname_alone = memory_lint.memory_dir(None)
            assert dirname_alone == neither, \
                f"CLAUDE_CODE_PROJECT_DIR_NAME must be ignored without CLAUDE_CONFIG_DIR, got {dirname_alone}"

            os.environ["CLAUDE_CONFIG_DIR"] = cfg
            both = memory_lint.memory_dir(None)
            assert both == os.path.join(cfg, "projects", "myrepo", "memory"), both

            os.environ.pop("CLAUDE_CODE_PROJECT_DIR_NAME", None)
            config_dir_alone = memory_lint.memory_dir(None)
            assert config_dir_alone == os.path.join(cfg, "projects", git_enc, "memory"), config_dir_alone
        finally:
            os.chdir(saved_cwd)
            for k, v in saved_env.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v


# --- 2026-08-23 mutation-testing probe: 13 weak-oracle survivors ---
# Each function below closes a mutant the probe found surviving: the code line
# was executed by some test, but no assertion observed the mutated behavior.
# Verified with per-mutant mutation-thinking (apply the flip, confirm the test
# now fails). See docs/research/mutation-probe-results-2026-08-23.md.

def test_measured_index_line_count_is_newlines_plus_one():
    # L208: `count("\n") + 1`. No prior test asserted the line-count half of the
    # (bytes, lines) tuple -- every caller ran with LINE_CAP huge so it never bound.
    b, lines = memory_lint.measured_index("a\nb\nc")
    assert lines == 3, lines   # 2 newlines -> 2+1==3; mutated 2-1==1
    assert b == 5, b


def test_near_budget_finding_fires_at_exactly_80_percent():
    # L349: `pct >= 80`. The NEAR-BUDGET finding differs from `pct > 80` only when
    # the integer pct lands on exactly 80. Set BYTE_CAP off the real index size so
    # the byte ratio is exactly 0.80 without hand-counting.
    orig_line, orig_byte = memory_lint.LINE_CAP, memory_lint.BYTE_CAP
    try:
        with tempfile.TemporaryDirectory() as d:
            _write_memory(d, "one.md", "project", "first pointer", "n/a")
            _write_memory(d, "two.md", "project", "second pointer", "n/a")
            with open(os.path.join(d, "MEMORY.md"), "w") as f:
                f.write("- [one](one.md) — a pointer hook for topic one here\n"
                         "- [two](two.md) — a pointer hook for topic two here\n")
            state = memory_lint.collect_state(d)
            memory_lint.LINE_CAP = 100_000     # keep the line ratio ~0, never over budget
            idx_bytes, idx_lines = memory_lint.measured_index(state["idx"])
            memory_lint.BYTE_CAP = int(idx_bytes / 0.80)   # byte ratio == 0.80 -> pct == 80
            pct = int(max(idx_lines / memory_lint.LINE_CAP,
                          idx_bytes / memory_lint.BYTE_CAP) * 100)
            assert pct == 80, (idx_bytes, memory_lint.BYTE_CAP, pct)   # loud setup guard
            findings, *_ = memory_lint.detector_findings(state)
            near = [f for f in findings if f.startswith("NEAR-BUDGET")]
            assert len(near) == 1, findings
            assert "at 80%" in near[0], near[0]   # interpolated pct, not the hardcoded cap string
    finally:
        memory_lint.LINE_CAP, memory_lint.BYTE_CAP = orig_line, orig_byte


def test_contradiction_candidates_excludes_stopwords_from_overlap():
    # L468: `w not in STOPWORDS`. A pair sharing ONLY a stopword must not surface.
    # Guards the documented 296-false-candidate regression the token filter prevents.
    with tempfile.TemporaryDirectory() as d:
        _write_memory(d, "alpha-db.md", "feedback", "alpha database indexing always", "rule one")
        _write_memory(d, "beta-fe.md", "feedback", "beta frontend rendering always", "rule two")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [alpha-db](alpha-db.md) — x\n- [beta-fe](beta-fe.md) — y\n")
        state = memory_lint.collect_state(d)
        pairset = lambda cands: {frozenset((c["a"], c["b"])) for c in cands}
        pair = frozenset(("alpha-db.md", "beta-fe.md"))
        # positive control: the pair IS reachable when the threshold can't exclude it
        # (else the oracle below would pass vacuously on a pipeline/type-match drift)
        assert pair in pairset(memory_lint.contradiction_candidates(state, min_overlap=0.0)), \
            "pipeline/type-match sanity"
        # oracle: only shared token is the stopword "always" -> correct overlap 0.0 fails 0.35;
        # mutated (keep-only-stopwords) overlap 1.0 clears it
        assert pair not in pairset(memory_lint.contradiction_candidates(state, min_overlap=0.35))


def test_contradiction_candidates_includes_pair_at_exact_overlap_threshold():
    # L515: `overlap >= min_overlap`. A pair whose overlap equals the threshold
    # exactly is included by `>=` but dropped by `>`. Tokens = stem + description:
    # A {alpha, keyword, banana}, B {beta, keyword, banana} -> 2/4 == 0.5 exact.
    with tempfile.TemporaryDirectory() as d:
        _write_memory(d, "alpha.md", "feedback", "keyword banana", "rule")
        _write_memory(d, "beta.md", "feedback", "keyword banana", "rule")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [alpha](alpha.md) — x\n- [beta](beta.md) — y\n")
        state = memory_lint.collect_state(d)
        cands = memory_lint.contradiction_candidates(state, min_overlap=0.5)
        assert frozenset(("alpha.md", "beta.md")) in {frozenset((c["a"], c["b"])) for c in cands}, cands


def test_find_patterns_resolves_shared_link_by_slug_not_only_stem():
    # L582: `t in stems or t in slug_set`. A [[link]] to a name-slug that differs
    # from the filename stem must still resolve (OR), not require both (AND).
    with tempfile.TemporaryDirectory() as d:
        for stem in ("a", "b", "c"):
            with open(os.path.join(d, f"{stem}.md"), "w") as f:
                f.write(f"---\nname: {stem}\n---\nsee [[hubslug]]\n")
        # hub file: stem 'hub-file' != slug 'hubslug', so the link resolves via slug only
        with open(os.path.join(d, "hub-file.md"), "w") as f:
            f.write("---\nname: hubslug\n---\na commonly cited hub\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [a](a.md) — x\n- [b](b.md) — y\n- [c](c.md) — z\n"
                     "- [hub-file](hub-file.md) — h\n")
        state = memory_lint.collect_state(d)
        clusters = memory_lint.pattern_clusters(state, 3)
        assert len(clusters) == 1, clusters   # mutated (AND): 'hubslug' not in stems -> no cluster
        assert set(clusters[0]["members"]) == {"a.md", "b.md", "c.md"}, clusters[0]


def test_find_patterns_shared_link_includes_target_linked_by_exactly_two_members():
    # L623: `sum(...) >= 2`. A target linked by exactly 2 cluster members belongs
    # in shared_links under `>=2` but is dropped by `>2`.
    with tempfile.TemporaryDirectory() as d:
        bodies = {"a": "see [[mainhub]] and [[pairtarget]]",
                  "b": "see [[mainhub]] and [[pairtarget]]",
                  "c": "see [[mainhub]]"}
        for stem, body in bodies.items():
            with open(os.path.join(d, f"{stem}.md"), "w") as f:
                f.write(f"---\nname: {stem}\n---\n{body}\n")
        for hub in ("mainhub", "pairtarget"):
            with open(os.path.join(d, f"{hub}.md"), "w") as f:
                f.write(f"---\nname: {hub}\n---\nn/a\n")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [a](a.md) — x\n- [b](b.md) — y\n- [c](c.md) — z\n"
                     "- [mainhub](mainhub.md) — m\n- [pairtarget](pairtarget.md) — p\n")
        state = memory_lint.collect_state(d)
        clusters = memory_lint.pattern_clusters(state, 3)
        assert len(clusters) == 1, clusters
        # mainhub links a,b,c (3); pairtarget links a,b (exactly 2) -> both are signatures
        assert "pairtarget" in clusters[0]["shared_links"], clusters[0]["shared_links"]


def test_git_fold_commits_credits_only_removed_pointers_not_added_or_context():
    # L777: the diff-scan guard `not line.startswith("-")`. A pointer that only ever
    # appeared as an ADDED or CONTEXT line must NOT be credited as a fold; only a
    # genuinely REMOVED pointer counts. Fold attribution is --classify-unindexed's
    # whole safety claim, and prior tests only truthy-checked the returned sha.
    with tempfile.TemporaryDirectory() as d:
        _init_git_repo(d)
        _write_memory(d, "keeper.md", "project", "stays indexed", "n/a")
        _write_memory(d, "gone.md", "project", "temporary", "n/a")
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [keeper](keeper.md) — stays\n")
        _git_commit(d, "add keeper pointer")   # keeper appears as an ADDED line
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [keeper](keeper.md) — stays\n- [gone](gone.md) — temp\n")
        _git_commit(d, "add gone pointer")      # keeper now a CONTEXT line
        with open(os.path.join(d, "MEMORY.md"), "w") as f:
            f.write("- [keeper](keeper.md) — stays\n")
        _git_commit(d, "fold: remove gone pointer")   # gone is REMOVED; keeper context
        folds, ok = memory_lint._git_fold_commits(d)
        assert ok
        assert "gone.md" in folds, folds        # positive control: a real removal IS credited
        assert "keeper.md" not in folds, folds   # oracle: added/context pointer must NOT be credited


def test_class_d_count_fold_skips_files_named_in_exclude_files():
    # L1187: `fname in exclude_files or fname not in state["files"]`. A file already
    # claimed by plan A/B (exclude_files) must be skipped. The missing-file half is
    # masked by the getmtime OSError guard, so only a nonempty exclude_files naming
    # an EXISTING file discriminates the `or`->`and` flip.
    orig_line, orig_byte = memory_lint.LINE_CAP, memory_lint.BYTE_CAP
    try:
        memory_lint.LINE_CAP = 10_000
        memory_lint.BYTE_CAP = 480
        with tempfile.TemporaryDirectory() as d:
            now = 2_000_000_000
            idx_lines = []
            for i in range(6):
                stem = f"topic-{i}"
                with open(os.path.join(d, f"{stem}.md"), "w") as f:
                    f.write(f"---\nname: {stem}\n---\nsome memory content about topic {i}\n")
                os.utime(os.path.join(d, f"{stem}.md"), (now + i * 100, now + i * 100))
                idx_lines.append(f"- [{stem}]({stem}.md) — a short pointer hook for topic {i} here")
            with open(os.path.join(d, "MEMORY.md"), "w") as f:
                f.write("\n".join(idx_lines) + "\n")
            state = memory_lint.collect_state(d)
            # topic-0 is the OLDEST (lowest mtime) -> the first fold candidate; excluding it
            # must remove it from the plan entirely.
            plan = memory_lint.class_d_count_fold(state, exclude_files={"topic-0.md"})
            assert plan, "fixture must actually fire Class D above the trigger"   # anti-vacuous
            assert "topic-0.md" not in [e["file"] for e in plan], plan
    finally:
        memory_lint.LINE_CAP, memory_lint.BYTE_CAP = orig_line, orig_byte


def test_class_d_break_is_inclusive_at_exact_byte_target():
    # L1199: `remaining_bytes <= target_bytes`. Inclusive stop at remaining==target.
    # BYTE_CAP=154 -> target_bytes=int(154*0.65)==100; index==200B in 24B lines,
    # 25B freed/fold: 200->175->150->125->100, break at 100<=100 after 4 folds.
    # Mutated (<): folds a 5th. Lines never bind (LINE_CAP huge).
    orig_line, orig_byte = memory_lint.LINE_CAP, memory_lint.BYTE_CAP
    try:
        memory_lint.LINE_CAP = 10_000_000
        memory_lint.BYTE_CAP = 154
        with tempfile.TemporaryDirectory() as d:
            lines = []
            for i in range(8):
                stem = f"t{i}"
                with open(os.path.join(d, f"{stem}.md"), "w") as f:
                    f.write(f"---\nname: {stem}\n---\ncontent\n")
                lines.append(f"- [{stem}]({stem}.md)" + "x" * 11)   # 13 + 11 == 24 bytes
            with open(os.path.join(d, "MEMORY.md"), "w") as f:
                f.write("\n".join(lines) + "\n")   # 8*24 + 8 newlines == 200 bytes
            state = memory_lint.collect_state(d)
            idx_bytes, _ = memory_lint.measured_index(state["idx"])
            assert idx_bytes == 200, idx_bytes   # loud fixture guard
            assert int(memory_lint.BYTE_CAP * memory_lint.FOLD_TARGET_PCT) == 100
            plan = memory_lint.class_d_count_fold(state, exclude_files=set())
            assert len(plan) == 4, [e["file"] for e in plan]   # mutated (<) -> 5
    finally:
        memory_lint.LINE_CAP, memory_lint.BYTE_CAP = orig_line, orig_byte


def test_class_d_break_is_inclusive_at_exact_line_target():
    # L1199: `remaining_lines <= target_lines` (the line half; needs its own fixture
    # because only one cap binds at a time). LINE_CAP=10 -> target_lines==6; index
    # is 9 lines, 1 dropped/fold: 9->8->7->6, break at 6<=6 after 3 folds.
    # Mutated (<): folds a 4th. Bytes never bind (BYTE_CAP huge).
    orig_line, orig_byte = memory_lint.LINE_CAP, memory_lint.BYTE_CAP
    try:
        memory_lint.LINE_CAP = 10
        memory_lint.BYTE_CAP = 10_000_000
        with tempfile.TemporaryDirectory() as d:
            lines = []
            for i in range(8):
                stem = f"t{i}"
                with open(os.path.join(d, f"{stem}.md"), "w") as f:
                    f.write(f"---\nname: {stem}\n---\ncontent\n")
                lines.append(f"- [{stem}]({stem}.md) — a pointer hook for topic {i}")
            with open(os.path.join(d, "MEMORY.md"), "w") as f:
                f.write("\n".join(lines) + "\n")   # 8 pointer lines -> 9 logical lines
            state = memory_lint.collect_state(d)
            _, idx_lines = memory_lint.measured_index(state["idx"])
            assert idx_lines == 9, idx_lines   # loud fixture guard
            assert int(memory_lint.LINE_CAP * memory_lint.FOLD_TARGET_PCT) == 6
            plan = memory_lint.class_d_count_fold(state, exclude_files=set())
            assert len(plan) == 3, [e["file"] for e in plan]   # mutated (<) -> 4
    finally:
        memory_lint.LINE_CAP, memory_lint.BYTE_CAP = orig_line, orig_byte


if __name__ == "__main__":
    test_typo_link_gets_suggestion()
    test_unrelated_dangling_link_gets_no_suggestion()
    test_markdown_style_dangling_link_is_detected()
    test_markdown_style_link_in_backticks_is_not_a_real_reference()
    test_markdown_style_link_with_path_is_treated_as_external_not_dangling()
    test_markdown_style_link_to_real_memory_resolves_and_avoids_false_orphan()
    test_class_d_count_fold_fires_over_trigger_and_reaches_target()
    test_class_d_count_fold_returns_nothing_under_trigger()
    test_template_compliance_flags_feedback_memory_missing_both_fields()
    test_contradiction_candidates_requires_matching_type()
    test_contradiction_candidates_pairs_high_overlap_same_type()
    test_contradiction_candidates_shared_link_is_context_not_an_independent_trigger()
    test_classify_unindexed_confirms_git_fold()
    test_classify_unindexed_flags_never_indexed_after_baseline()
    test_classify_unindexed_flags_ambiguous_when_pre_baseline()
    test_classify_unindexed_pre_baseline_file_edited_later_stays_ambiguous()
    test_classify_unindexed_handles_no_git_repo()
    test_classify_unindexed_no_substring_collision()
    test_classify_unindexed_no_prose_mention_false_fold()
    test_classify_unindexed_failed_git_query_is_safe_not_never_indexed()
    test_classify_unindexed_git_call_count_stays_constant_regardless_of_file_count()
    test_unindexed_file_linked_from_indexed_memory_is_context_layer_not_a_finding()
    test_unindexed_and_unreachable_file_still_fires_unindexed()
    test_context_layer_reachability_is_transitive_through_unindexed_files()
    test_find_patterns_clusters_by_shared_link()
    test_find_patterns_cli_default_caps_giant_component()
    test_find_patterns_reports_hidden_count_when_everything_is_capped_out()
    test_find_patterns_json_prompt_includes_prompts()
    test_find_patterns_cli_boundary_at_exact_cap_size()
    test_memory_dir_project_dir_name_requires_config_dir()
    # 2026-08-23 mutation-probe weak-oracle closers
    test_measured_index_line_count_is_newlines_plus_one()
    test_near_budget_finding_fires_at_exactly_80_percent()
    test_contradiction_candidates_excludes_stopwords_from_overlap()
    test_contradiction_candidates_includes_pair_at_exact_overlap_threshold()
    test_find_patterns_resolves_shared_link_by_slug_not_only_stem()
    test_find_patterns_shared_link_includes_target_linked_by_exactly_two_members()
    test_git_fold_commits_credits_only_removed_pointers_not_added_or_context()
    test_class_d_count_fold_skips_files_named_in_exclude_files()
    test_class_d_break_is_inclusive_at_exact_byte_target()
    test_class_d_break_is_inclusive_at_exact_line_target()
    print("OK")
