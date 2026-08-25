#!/usr/bin/env python3
"""Self-check for verify-preserved.py's extraction regexes. Run directly:
    python3 tests/skills/compress-docs/test_verify_preserved.py
No framework, no fixtures — plain asserts, run top to bottom.
"""
import importlib.util
from pathlib import Path

# hyphenated filename can't be imported by name — load it by path instead.
# SUT (verify-preserved.py) lives at skills/meta/compress-docs/scripts/ —
# tests/ doesn't move with the skills/ bucket migration (2026-08-25), so the
# "../../.." hop count up to repo root is unchanged; only the "meta" segment
# is new, inserted where the old flat "compress-docs" path used to start.
spec = importlib.util.spec_from_file_location("verify_preserved",
    Path(__file__).parent / ".." / ".." / ".." / "skills" / "meta" / "compress-docs" / "scripts" / "verify-preserved.py")
assert spec and spec.loader, "could not locate verify-preserved.py next to this test"
vp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vp)

# --- link URLs ---------------------------------------------------------

assert vp.extract_link_urls("[text](https://example.com)") == ["https://example.com"], \
    "plain link regressed"

assert vp.extract_link_urls('[text](https://example.com "Title")') == ["https://example.com"], \
    "titled link (double-quoted) not tracked"

assert vp.extract_link_urls("[text](https://example.com 'Title')") == ["https://example.com"], \
    "titled link (single-quoted) not tracked"

assert vp.extract_link_urls("[text][ref]\n\n[ref]: https://example.com") == ["https://example.com"], \
    "reference-style link definition not tracked"

assert vp.extract_link_urls("[text][ref]") == [], \
    "reference-style usage alone (no definition) should yield no URL, not a false one"

# --- inline code spans ---------------------------------------------------

assert vp.extract_inline_code("`plain`") == ["plain"], "single-backtick span regressed"

assert vp.extract_inline_code("``code with a ` backtick inside``") == ["code with a ` backtick inside"], \
    "double-backtick span not tracked"

assert vp.extract_inline_code("`single` and ``double with ` backtick``") == [
    "single",
    "double with ` backtick",
], "single and double backtick spans on the same line should both be tracked, no double-counting"

# --- occurrence-count still catches a real drop ---------------------------

before = vp.extract_link_urls('See [docs](https://a.example "A") and [more][ref]\n\n[ref]: https://b.example')
after = vp.extract_link_urls('See [docs](https://a.example "A")')
assert vp.diff_counts(before, after) is not None, \
    "dropping a reference-style link's URL must still be caught as a regression"

print("PASS: all verify-preserved.py extraction checks hold.")
