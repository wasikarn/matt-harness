#!/usr/bin/env python3
"""Self-check for the dangling-link did-you-mean suggestion. Run directly: python3 test_memory_lint.py"""
import importlib.util
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
    print("OK")
