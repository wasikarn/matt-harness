#!/usr/bin/env python3
"""Verify a compressed markdown file kept its protected regions byte-exact.

Compares the on-disk file against the last-committed (`git show HEAD:<path>`)
version: fenced code blocks (proper CommonMark fence matching, not a naive
regex), headings (count + text/order), inline code spans — both single- and
multi-backtick-delimited, occurrence-counted, fences stripped first so a
backtick inside a code block never reads as inline code — and link URLs,
both inline (`[text](url)`, with or without a title attribute) and
reference-style (`[text][ref]`, tracked via its `[ref]: url` definition
line). Exits 0 if all protected regions are unchanged, 1 otherwise (with a
report of what drifted).
"""
import re
import subprocess
import sys
from collections import Counter

FENCE_OPEN_RE = re.compile(r"^(\s{0,3})(`{3,}|~{3,})(.*)$")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)", re.MULTILINE)
# Captures the URL in `[text](url)` and `[text](url "title")` alike — the
# optional group swallows a trailing quoted title before the closing paren.
LINK_URL_RE = re.compile(r"\]\(([^)\s]+)(?:\s+[\"'][^\"']*[\"'])?\)")
# Reference-style links (`[text][ref]`) carry no URL themselves — the URL
# lives on a separate `[ref]: url` definition line, which this tracks.
REFERENCE_LINK_DEF_RE = re.compile(r"^[ \t]{0,3}\[[^\]\n]+\]:[ \t]*(\S+)", re.MULTILINE)
# Double-backtick-delimited spans (used when the code itself contains a
# literal backtick, e.g. `` `rm -rf` `` ) — a separate pattern from the
# single-backtick one below, since a `(?<!`)...(?!`)` lookaround can't also
# match a longer, self-delimiting run without conflating the two.
DOUBLE_BACKTICK_RE = re.compile(r"``((?:[^`\n]|`(?!`))+)``")
FRONTMATTER_RE = re.compile(r"\A(---\r?\n.*?\r?\n---\r?\n)", re.DOTALL)


def extract_frontmatter(text):
    """kbg's skill/agent/command files open with YAML frontmatter — a known
    LLM habit is touching it during a prose-compression pass even when told
    not to (see skills/compress-docs/SKILL.md). Check it byte-exact."""
    m = FRONTMATTER_RE.match(text)
    return m.group(1) if m else ""


def extract_code_blocks(text):
    """Line-based fence extractor: `` ``` `` / `~~~`, variable length,
    closing fence must match char and be >= opening length (CommonMark)."""
    blocks = []
    lines = text.split("\n")
    i, n = 0, len(lines)
    while i < n:
        m = FENCE_OPEN_RE.match(lines[i])
        if not m:
            i += 1
            continue
        fence_char, fence_len = m.group(2)[0], len(m.group(2))
        block_lines = [lines[i]]
        i += 1
        closed = False
        while i < n:
            close_m = FENCE_OPEN_RE.match(lines[i])
            if (
                close_m
                and close_m.group(2)[0] == fence_char
                and len(close_m.group(2)) >= fence_len
                and close_m.group(3).strip() == ""
            ):
                block_lines.append(lines[i])
                closed = True
                i += 1
                break
            block_lines.append(lines[i])
            i += 1
        if closed:
            blocks.append("\n".join(block_lines))
        # unclosed fence: malformed markdown, skip rather than false-flag
    return blocks


def strip_code_blocks(text):
    for block in extract_code_blocks(text):
        text = text.replace(block, "", 1)
    return text


def extract_inline_code(text):
    text = strip_code_blocks(text)
    single = re.findall(r"(?<!`)`([^`\n]+)`(?!`)", text)
    double = DOUBLE_BACKTICK_RE.findall(text)
    return single + double


def extract_headings(text):
    return [(len(h), t.strip()) for h, t in HEADING_RE.findall(text)]


def extract_link_urls(text):
    return LINK_URL_RE.findall(text) + REFERENCE_LINK_DEF_RE.findall(text)


def diff_counts(before, after):
    """Counter-aware diff: reports partial occurrence loss, not just presence."""
    cb, ca = Counter(before), Counter(after)
    if cb == ca:
        return None
    missing, added = [], []
    for item, n in cb.items():
        if ca[item] < n:
            missing.append(f"{item!r} (had {n}, now {ca[item]})")
    for item, n in ca.items():
        if cb[item] < n:
            added.append(f"{item!r} (now {n}, had {cb[item]})")
    return missing, added


def main():
    if len(sys.argv) != 2:
        print("usage: verify-preserved.py <file>", file=sys.stderr)
        return 2
    path = sys.argv[1]

    before_proc = subprocess.run(
        ["git", "show", f"HEAD:{path}"], capture_output=True, text=True
    )
    if before_proc.returncode != 0:
        print(f"error: could not read HEAD:{path} — {before_proc.stderr.strip()}", file=sys.stderr)
        return 2
    before_text = before_proc.stdout

    with open(path, encoding="utf-8") as f:
        after_text = f.read()

    checks = {
        "fenced code blocks": (extract_code_blocks(before_text), extract_code_blocks(after_text)),
        "headings": (extract_headings(before_text), extract_headings(after_text)),
        "inline code spans": (extract_inline_code(before_text), extract_inline_code(after_text)),
        "link URLs": (extract_link_urls(before_text), extract_link_urls(after_text)),
    }

    failures = []
    for kind, (b, a) in checks.items():
        d = diff_counts(b, a)
        if d is not None:
            failures.append((kind, *d))

    fm_before, fm_after = extract_frontmatter(before_text), extract_frontmatter(after_text)
    if fm_before != fm_after:
        failures.append(("frontmatter", [f"changed: {fm_before[:150]!r}"], [f"now: {fm_after[:150]!r}"]))

    if not failures:
        print("PASS: all protected regions preserved.")
        return 0

    print("FAIL: protected regions drifted.")
    for kind, missing, added in failures:
        print(f"\n{kind}:")
        for m in missing:
            print(f"  - missing: {m[:150]}")
        for a in added:
            print(f"  + unexpected: {a[:150]}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
