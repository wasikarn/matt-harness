#!/usr/bin/env python3
"""Regression test for scripts/autotrigger/events.py's load_custom_names.

Guards the bucket-folder migration (2026-08-25): skills moved from
skills/<name>/SKILL.md to skills/<bucket>/<name>/SKILL.md. A one-level-only
directory walk silently discovers zero skills against the new layout with
no exception — exactly the failure mode this test catches.
Run standalone: python3 tests/scripts/test_autotrigger_events.py
"""
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "autotrigger"))
import events  # noqa: E402


class TestLoadCustomNames(unittest.TestCase):
    def test_discovers_bucketed_skills(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            skill_dir = root / "claude" / "skills" / "meta" / "harness-audit"
            skill_dir.mkdir(parents=True)
            (skill_dir / "SKILL.md").write_text("---\nname: harness-audit\n---\nbody\n")
            names, _ = events.load_custom_names(root)
            self.assertIn("harness-audit", names)
            self.assertFalse(names["harness-audit"])

    def test_discovers_flat_skills(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            skill_dir = root / "claude" / "skills" / "frame"
            skill_dir.mkdir(parents=True)
            (skill_dir / "SKILL.md").write_text("---\nname: frame\n---\nbody\n")
            names, _ = events.load_custom_names(root)
            self.assertIn("frame", names)

    def test_underscore_dirs_excluded_at_both_depths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "claude" / "skills" / "_scaffold" / "SKILL.md").parent.mkdir(parents=True)
            (root / "claude" / "skills" / "_scaffold" / "SKILL.md").write_text("body")
            (root / "claude" / "skills" / "meta" / "_draft" / "SKILL.md").parent.mkdir(parents=True)
            (root / "claude" / "skills" / "meta" / "_draft" / "SKILL.md").write_text("body")
            names, _ = events.load_custom_names(root)
            self.assertEqual(names, {})

    def test_dmi_flag_survives_bucket_depth(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            skill_dir = root / "claude" / "skills" / "meta" / "ship-merge"
            skill_dir.mkdir(parents=True)
            (skill_dir / "SKILL.md").write_text(
                "---\nname: ship-merge\ndisable-model-invocation: true\n---\nbody\n"
            )
            names, _ = events.load_custom_names(root)
            self.assertTrue(names["ship-merge"])


if __name__ == "__main__":
    unittest.main()
