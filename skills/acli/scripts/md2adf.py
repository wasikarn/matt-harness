#!/usr/bin/env python3
"""md2adf — convert a small Markdown subset into Atlassian Document Format (ADF).

ADF is the format Jira requires for work-item descriptions and comments passed
via `acli ... --from-json`. Hand-writing the nested JSON is error-prone; this
turns the Markdown people actually write into a valid ADF document.

Usage:
  python3 md2adf.py DESC.md                       # print ADF doc object
  python3 md2adf.py - < DESC.md                   # read Markdown from stdin
  python3 md2adf.py DESC.md -s "Summary" -p TP -t Bug [-l a,b]
                                                  # print a full create payload
                                                  # (description = ADF) for
                                                  # `acli jira workitem create --from-json`

Supported Markdown: #/##/### headings, ordered/bullet/task (`- [ ]`) lists,
**bold**, *italic*, `code`, ~~strike~~, [text](url) links, ``` code blocks,
> blockquotes, --- horizontal rules, blank-line-separated paragraphs.
Nested lists are flattened — use H3 sub-headings + flat bullets instead.
Anything else is kept as literal paragraph text (ADF text is literal — matches acli).

Fails loud (exit 1) on empty input or a heading with no text.
"""
import argparse
import json
import re
import sys
import uuid

INLINE_RE = re.compile(
    r'\*\*(?P<bold_text>[^*]+)\*\*'
    r'|\[(?P<link_text>[^\]]+)\]\((?P<link_url>[^)]+)\)'
    r'|`(?P<code_text>[^`]+)`'
    r'|\*(?P<italic_text>[^*]+)\*'
    r'|_(?P<italic2_text>[^_]+)_'
    r'|~~(?P<strike_text>[^~]+)~~'
)


def _emit_text(nodes, s):
    if s:
        nodes.append({"type": "text", "text": s})


def inline(text):
    """Parse a line into ADF inline text nodes (single-pass finditer)."""
    nodes = []
    pos = 0
    for m in INLINE_RE.finditer(text):
        if m.start() > pos:
            _emit_text(nodes, text[pos:m.start()])
        gd = m.groupdict()
        if gd.get("bold_text") is not None:
            nodes.append({"type": "text", "text": gd["bold_text"],
                          "marks": [{"type": "strong"}]})
        elif gd.get("link_text") is not None:
            nodes.append({"type": "text", "text": gd["link_text"],
                          "marks": [{"type": "link", "attrs": {"href": gd["link_url"]}}]})
        elif gd.get("code_text") is not None:
            nodes.append({"type": "text", "text": gd["code_text"],
                          "marks": [{"type": "code"}]})
        elif gd.get("italic_text") is not None:
            nodes.append({"type": "text", "text": gd["italic_text"],
                          "marks": [{"type": "em"}]})
        elif gd.get("italic2_text") is not None:
            nodes.append({"type": "text", "text": gd["italic2_text"],
                          "marks": [{"type": "em"}]})
        elif gd.get("strike_text") is not None:
            nodes.append({"type": "text", "text": gd["strike_text"],
                          "marks": [{"type": "strike"}]})
        pos = m.end()
    if pos < len(text):
        _emit_text(nodes, text[pos:])
    return nodes or [{"type": "text", "text": text}]


def parse(md):
    lines = md.replace("\r\n", "\n").split("\n")
    content = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()
        if not stripped:
            i += 1
            continue
        # Horizontal rule
        if re.match(r"^(\*{3,}|-{3,}|_{3,})\s*$", stripped):
            content.append({"type": "rule"})
            i += 1
            continue
        # Heading
        m = re.match(r"^(#{1,3})\s+(.*)$", stripped)
        if m:
            text = m.group(2).strip()
            if not text:
                sys.exit(f"FATAL: empty heading on line {i + 1}")
            content.append({"type": "heading",
                            "attrs": {"level": len(m.group(1))},
                            "content": inline(text)})
            i += 1
            continue
        # Code block
        if stripped.startswith("```"):
            lang = stripped[3:].strip()
            i += 1
            code_lines = []
            while i < n and not lines[i].strip().startswith("```"):
                code_lines.append(lines[i])
                i += 1
            if i < n:
                i += 1  # skip closing fence
            body = "\n".join(code_lines)
            content.append({"type": "codeBlock", "attrs": {"language": lang},
                          "content": [{"type": "text", "text": body}]})
            continue
        # Blockquote
        if stripped.startswith("> "):
            quote_lines = []
            while i < n and lines[i].strip().startswith("> "):
                quote_lines.append(lines[i].strip()[2:])
                i += 1
            quote_md = "\n".join(quote_lines)
            quote_content = []
            for para in quote_md.split("\n\n"):
                para = para.strip()
                if para:
                    quote_content.append({"type": "paragraph", "content": inline(para)})
            content.append({"type": "blockquote", "content": quote_content})
            continue
        # Task list
        task = re.match(r"^[-*]\s+\[([ xX])\]\s*(.*)$", stripped)
        if task:
            items = []
            while i < n and lines[i].strip():
                mm = re.match(r"^[-*]\s+\[([ xX])\]\s*(.*)$", lines[i].strip())
                if not mm:
                    break
                state = "DONE" if mm.group(1).lower() == "x" else "TODO"
                # Jira requires a localId on every taskItem and the taskList, and
                # taskItem content must be inline nodes directly — NOT wrapped in a
                # paragraph. Getting either wrong makes Jira reject the whole payload
                # with INVALID_INPUT (verified TP-636). uuid4 hex is a valid localId.
                items.append({"type": "taskItem",
                              "attrs": {"localId": uuid.uuid4().hex, "state": state},
                              "content": inline(mm.group(2))})
                i += 1
            content.append({"type": "taskList",
                            "attrs": {"localId": uuid.uuid4().hex},
                            "content": items})
            continue
        # List block (ordered or bullet) — consecutive matching lines
        ol = re.match(r"^\d+\.\s+(.*)$", stripped)
        ul = re.match(r"^[-*]\s+(.*)$", stripped)
        if ol or ul:
            ordered = ol is not None
            pat = r"^\d+\.\s+(.*)$" if ordered else r"^[-*]\s+(.*)$"
            items = []
            while i < n and lines[i].strip():
                mm = re.match(pat, lines[i].strip())
                if not mm:
                    break
                items.append(mm.group(1).strip())
                i += 1
            content.append({
                "type": "orderedList" if ordered else "bulletList",
                "content": [{"type": "listItem",
                             "content": [{"type": "paragraph", "content": inline(it)}]}
                            for it in items],
            })
            continue
        # Paragraph — consecutive plain lines until blank/special
        buf = []
        while i < n and lines[i].strip():
            s = lines[i].strip()
            if re.match(r"^(#{1,3})\s+|^\d+\.\s+|^[-*]\s+|^>\s*|^```\s*|^(\*{3,}|-{3,}|_{3,})\s*$", s):
                break
            buf.append(s)
            i += 1
        content.append({"type": "paragraph", "content": inline(" ".join(buf))})
    if not content:
        sys.exit("FATAL: no content — input was empty")
    return {"type": "doc", "version": 1, "content": content}


def main():
    ap = argparse.ArgumentParser(description="Convert Markdown to ADF for acli --from-json")
    ap.add_argument("file", help="Markdown file, or '-' for stdin")
    ap.add_argument("-s", "--summary", help="wrap into a create payload with this summary")
    ap.add_argument("-p", "--project", help="projectKey for the create payload")
    ap.add_argument("-t", "--type", help="work item type for the create payload (e.g. Bug)")
    ap.add_argument("-l", "--labels", help="comma-separated labels for the create payload")
    ap.add_argument("-P", "--parent", help="parent work-item key for a sub-task (sets parentIssueId)")
    args = ap.parse_args()

    md = sys.stdin.read() if args.file == "-" else open(args.file, encoding="utf-8").read()
    adf = parse(md)

    if args.summary or args.project or args.type or args.parent:
        if not (args.summary and args.project and args.type):
            sys.exit("FATAL: a create payload needs all of -s/--summary, -p/--project, -t/--type")
        payload = {"summary": args.summary, "projectKey": args.project,
                   "type": args.type, "description": adf}
        if args.parent:
            payload["parentIssueId"] = args.parent
        if args.labels:
            payload["labels"] = [x.strip() for x in args.labels.split(",") if x.strip()]
        out = payload
    else:
        out = adf

    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
