#!/usr/bin/env python3
"""acli-edit — read-modify-write a Jira description without destroying it.

`acli jira workitem edit --description` REPLACES the whole description; this
merges the ADF instead, so existing content survives.

Usage:
  python3 acli-edit.py MODE KEY CUR.json PAYLOAD.json [NEW.json] [HEADING]

Modes: append | remove | replace
"""
import json, sys


def _text(node):
    return "".join(
        t.get("text", "") for t in node.get("content", []) if t.get("type") == "text"
    ).strip()


def _section_end(nodes, start):
    lvl = nodes[start].get("attrs", {}).get("level", 1)
    j = start + 1
    while j < len(nodes):
        m = nodes[j]
        if m.get("type") == "heading" and m.get("attrs", {}).get("level", 99) <= lvl:
            break
        j += 1
    return j


def _new_content(path):
    with open(path) as f:
        new = json.load(f)
    nc = new.get("content", []) if isinstance(new, dict) and new.get("type") == "doc" else []
    if not nc:
        sys.exit("FATAL: new content is empty")
    return nc


def merge(mode, key, cur_f, out_f, new_f, heading):
    with open(cur_f) as f:
        cur = json.load(f)
    cur = cur[0] if isinstance(cur, list) else cur
    desc = (cur.get("fields") or {}).get("description") or {"type": "doc", "version": 1, "content": []}
    nodes = desc.get("content", [])

    if mode == "append":
        desc["content"] = nodes + _new_content(new_f)
    elif mode == "remove":
        out, i, removed = [], 0, 0
        while i < len(nodes):
            if nodes[i].get("type") == "heading" and _text(nodes[i]) == heading.strip():
                removed += 1
                i = _section_end(nodes, i)
                continue
            out.append(nodes[i])
            i += 1
        if removed == 0:
            sys.exit(f"FATAL: no section with heading '{heading}' — nothing removed")
        desc["content"] = out
        sys.stderr.write(f"removed {removed} section(s) matching '{heading}'\n")
    elif mode == "replace":
        s = next((i for i, n in enumerate(nodes)
                  if n.get("type") == "heading" and _text(n) == heading.strip()), None)
        if s is None:
            sys.exit(f"FATAL: no section with heading '{heading}' — nothing replaced")
        e = _section_end(nodes, s)
        desc["content"] = nodes[:s] + _new_content(new_f) + nodes[e:]
        sys.stderr.write(f"replaced section '{heading}' in place\n")

    with open(out_f, "w") as f:
        json.dump({"issues": [key], "description": desc}, f, ensure_ascii=False)


if __name__ == "__main__":
    if len(sys.argv) < 5:
        sys.exit("usage: acli-edit.py MODE KEY CUR.json PAYLOAD.json [NEW.json] [HEADING]")
    mode, key, cur_f, out_f = sys.argv[1:5]
    new_f = sys.argv[5] if len(sys.argv) > 5 else ""
    heading = sys.argv[6] if len(sys.argv) > 6 else ""
    merge(mode, key, cur_f, out_f, new_f, heading)
