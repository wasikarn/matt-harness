#!/usr/bin/env python3
"""adf2md — render ADF (or a full acli view payload) as readable Markdown.

The inverse of md2adf. `acli jira workitem view KEY --json` returns a large ADF
description buried under ~60 null customfields, avatar URLs, and self links —
expensive to read and hard to scan. This flattens it to compact Markdown.

Usage:
  acli jira workitem view TP-1 --json | python3 adf2md.py   # → readable work-item card
  python3 adf2md.py desc.json                               # bare ADF doc → Markdown
  python3 adf2md.py - < payload.json                        # stdin

Auto-detects input: a full view payload (has `fields`) prints a work-item card
(key · type · status, metadata, description, comments); a bare ADF `{type:doc}`
prints just the body. Fails loud (exit 1) on invalid JSON.
"""
import argparse
import json
import sys


# ── inline ───────────────────────────────────────────────────────────

def render_text(node):
    t = node.get("text", "")
    marks = {m["type"]: m for m in node.get("marks", [])}
    if "code" in marks:
        t = f"`{t}`"
    if "strong" in marks:
        t = f"**{t}**"
    if "em" in marks:
        t = f"*{t}*"
    if "strike" in marks:
        t = f"~~{t}~~"
    if "link" in marks:
        t = f"[{t}]({marks['link'].get('attrs', {}).get('href', '')})"
    return t


def inline(nodes):
    out = []
    for n in nodes or []:
        ty = n.get("type")
        if ty == "text":
            out.append(render_text(n))
        elif ty == "hardBreak":
            out.append("\n")
        elif ty in ("emoji", "mention"):
            attrs = n.get("attrs", {})
            out.append(attrs.get("text") or attrs.get("shortName") or "")
        else:
            out.append(inline(n.get("content", [])))
    return "".join(out)


# ── blocks ───────────────────────────────────────────────────────────

def render_block(node, indent=0):
    ty = node.get("type")
    pad = "  " * indent
    if ty == "heading":
        lvl = node.get("attrs", {}).get("level", 2)
        return "#" * lvl + " " + inline(node.get("content", []))
    if ty == "paragraph":
        return pad + inline(node.get("content", []))
    if ty in ("bulletList", "orderedList"):
        ordered = ty == "orderedList"
        lines = []
        for i, li in enumerate(node.get("content", []), 1):
            marker = f"{i}." if ordered else "-"
            sub = [render_block(c, indent + 1) for c in li.get("content", [])]
            # First child shares the bullet line; the rest keep their indent.
            first = sub[0].lstrip() if sub else ""
            lines.append(f"{pad}{marker} {first}")
            lines.extend(s for s in sub[1:] if s.strip())
        return "\n".join(lines)
    if ty == "taskList":
        lines = []
        for ti in node.get("content", []):
            box = "x" if ti.get("attrs", {}).get("state") == "DONE" else " "
            lines.append(f"{pad}- [{box}] {inline(ti.get('content', []))}")
        return "\n".join(lines)
    if ty == "codeBlock":
        lang = node.get("attrs", {}).get("language", "")
        body = inline(node.get("content", []))
        return f"```{lang}\n{body}\n```"
    if ty == "blockquote":
        inner = "\n".join(render_block(c) for c in node.get("content", []))
        return "\n".join("> " + ln for ln in inner.split("\n"))
    if ty == "panel":
        ptype = node.get("attrs", {}).get("panelType", "info").upper()
        inner = "\n".join(render_block(c) for c in node.get("content", []))
        return "\n".join(f"> {ln}" for ln in (f"[{ptype}]\n" + inner).split("\n"))
    if ty == "rule":
        return "---"
    if ty == "table":
        return render_table(node)
    if ty in ("mediaSingle", "mediaGroup", "media"):
        return "_[attachment]_"
    # Unknown container — recurse so nothing is silently dropped.
    if node.get("content"):
        return "\n\n".join(render_block(c, indent) for c in node["content"])
    return inline(node.get("content", []))


def render_table(node):
    rows = []
    for row in node.get("content", []):
        cells = [inline_cell(c) for c in row.get("content", [])]
        rows.append("| " + " | ".join(cells) + " |")
    if not rows:
        return ""
    header_sep = "| " + " | ".join("---" for _ in node["content"][0]["content"]) + " |"
    return "\n".join([rows[0], header_sep] + rows[1:])


def inline_cell(cell):
    return " ".join(inline(c.get("content", [])) for c in cell.get("content", [])).strip()


def render_doc(doc):
    return "\n\n".join(render_block(b) for b in doc.get("content", [])).strip()


# ── work-item card ─────────────────────────────────────────────────────

def render_card(payload):
    f = payload.get("fields", {})
    key = payload.get("key", "?")
    itype = (f.get("issuetype") or {}).get("name", "")
    status = (f.get("status") or {}).get("name", "")
    summary = f.get("summary", "")
    head = f"# {key} · {itype}" + (f" · {status}" if status else "")

    meta = []
    a = f.get("assignee")
    if a:
        meta.append(f"**Assignee:** {a.get('displayName') or a.get('emailAddress')}")
    pr = f.get("priority")
    if pr:
        meta.append(f"**Priority:** {pr.get('name')}")
    parent = f.get("parent")
    if parent:
        meta.append(f"**Parent:** {parent.get('key')}")
    labels = f.get("labels")
    if labels:
        meta.append(f"**Labels:** {', '.join(labels)}")

    parts = [head, summary]
    if meta:
        parts.append("  ".join(meta))
    desc = f.get("description")
    if desc:
        parts.append("## Description\n\n" + render_doc(desc))
    comments = ((f.get("comment") or {}).get("comments")) or []
    if comments:
        lines = [f"## Comments ({len(comments)})"]
        for c in comments:
            who = (c.get("author") or {}).get("displayName", "?")
            lines.append(f"**{who}:** " + render_doc(c["body"]) if isinstance(c.get("body"), dict)
                         else f"**{who}:** {c.get('body', '')}")
        parts.append("\n\n".join(lines))
    return "\n\n".join(p for p in parts if p and p.strip())


def render_create_card(data):
    """Render a flat acli create-payload (`--from-json` shape) as a preview card.

    A create-payload uses flat top-level keys (summary/projectKey/type/labels/
    description/parentIssueId/[priority/assignee]) with NO `fields` wrapper, so
    render_card's header would print a blank `# ? ·` and silently drop the
    project/type/priority — exactly the metadata most worth eyeballing before an
    outward-facing create. This surfaces it so a create preview is trustworthy.
    """
    itype = data.get("type", "")
    head = ("# (new) " + itype).rstrip()

    meta = []
    proj = data.get("projectKey")
    if proj:
        meta.append(f"**Project:** {proj}")
    pr = data.get("priority")
    if pr:
        meta.append(f"**Priority:** {pr.get('name') if isinstance(pr, dict) else pr}")
    parent = data.get("parentIssueId")
    if parent:
        meta.append(f"**Parent:** {parent}")
    assignee = data.get("assignee")
    if assignee:
        meta.append(f"**Assignee:** {assignee.get('name') if isinstance(assignee, dict) else assignee}")
    labels = data.get("labels")
    if labels:
        meta.append(f"**Labels:** {', '.join(labels)}")

    parts = [head, data.get("summary", "")]
    if meta:
        parts.append("  ".join(meta))
    desc = data.get("description")
    if isinstance(desc, dict):
        parts.append("## Description\n\n" + render_doc(desc))
    return "\n\n".join(p for p in parts if p and p.strip())


def main():
    ap = argparse.ArgumentParser(description="Render ADF / acli view payload as Markdown")
    ap.add_argument("file", nargs="?", default="-", help="JSON file, or '-'/omitted for stdin")
    args = ap.parse_args()
    raw = sys.stdin.read() if args.file == "-" else open(args.file, encoding="utf-8").read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.exit(f"FATAL: invalid JSON: {e}")

    if isinstance(data, list):
        if not data:
            sys.exit("FATAL: empty array")
        print("\n\n---\n\n".join(_one(d) for d in data))
    else:
        print(_one(data))


def _one(data):
    if isinstance(data, dict) and data.get("type") == "doc":
        return render_doc(data)
    if isinstance(data, dict) and "fields" in data:
        return render_card(data)
    if isinstance(data, dict) and "description" in data and isinstance(data["description"], dict):
        return render_create_card(data)  # bare create-payload shape (flat keys, no `fields` wrapper)
    sys.exit("FATAL: unrecognized input — expected an ADF doc or an acli view payload")


if __name__ == "__main__":
    main()
