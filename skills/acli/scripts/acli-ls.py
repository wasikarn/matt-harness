#!/usr/bin/env python3
"""acli-ls — render `acli jira workitem search --json` as an aligned table.

Captures the single most-rewritten acli-adjacent pattern: piping search JSON into
an ad-hoc python printer. It bakes in the two things every one-off reinvents:

  - the list-or-dict unwrap — acli has returned a bare list AND a dict keyed
    issues / workItems / values across versions/commands;
  - the nested-field guards — status / issuetype / parent / assignee are each
    dict-or-None, so naive `f['status']['name']` crashes on unassigned/no-parent.

Columns: key · type · status · parent · assignee · summary. Reads stdin.
Fails loud (exit 1) on invalid JSON; prints "(no matches)" on an empty set.
"""
import json
import sys


def _name(v):
    return v.get("name", "") if isinstance(v, dict) else ""


def _person(v):
    return (v.get("displayName") or v.get("emailAddress") or "") if isinstance(v, dict) else ""


def main():
    raw = sys.stdin.read()
    try:
        d = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.exit(f"FATAL: invalid JSON: {e}")

    # list-or-dict unwrap — tolerate every shape acli has emitted
    if isinstance(d, list):
        rows = d
    elif isinstance(d, dict):
        rows = d.get("issues") or d.get("workItems") or d.get("values") or []
    else:
        sys.exit("FATAL: unrecognized search payload")

    if not rows:
        print("(no matches)")
        return

    table = []
    for it in rows:
        f = it.get("fields", {}) if isinstance(it, dict) else {}
        parent = f.get("parent")
        table.append([
            it.get("key", "?"),
            _name(f.get("issuetype")),
            _name(f.get("status")),
            ("p:" + parent["key"]) if isinstance(parent, dict) and parent.get("key") else "-",
            _person(f.get("assignee")) or "-",
            (f.get("summary") or "").strip(),
        ])

    # width-align all columns except the trailing summary
    widths = [max(len(r[i]) for r in table) for i in range(5)]
    for r in table:
        cells = "  ".join(r[i].ljust(widths[i]) for i in range(5))
        print(f"{cells}  {r[5]}")
    print(f"\n{len(table)} item(s)", file=sys.stderr)


if __name__ == "__main__":
    main()
