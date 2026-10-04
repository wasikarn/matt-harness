#!/usr/bin/env python3
"""Resolve a Codex model tier to a catalog slug: codex-resolve-model.py <tier> [--effort E]

Prints the best visible model whose slug ends in -<tier> (lowest `priority`, visibility "list")
from the catalog Codex caches itself ($CODEX_HOME/models_cache.json, default ~/.codex). With
--effort, only models that list that effort in supported_reasoning_levels qualify, so an effort
the newest model lacks falls to the next one that has it. Exit 1 with a reason on stderr and
nothing on stdout when no catalog, no such tier or no model supports the effort: the caller then
follows docs/reference/codex-integration-map.md (pick an available model, disclose the swap).
The caller must name the resolved slug in its report; it is not a pin.
"""
import json
import os
import sys


def fail(msg):
    print(f"codex-resolve-model: {msg}", file=sys.stderr)
    return 1


def main(argv):
    args = argv[1:]
    effort = None
    if "--effort" in args:
        i = args.index("--effort")
        if i + 1 >= len(args):
            return fail("--effort needs a value")
        effort = args[i + 1]
        del args[i:i + 2]
    if len(args) != 1:
        return fail("usage: codex-resolve-model.py <tier> [--effort E]")
    tier = args[0].lower()

    path = os.path.join(os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"), "models_cache.json")
    try:
        with open(path) as f:
            models = json.load(f).get("models", [])
    except OSError:
        return fail(f"no catalog at {path}")
    except (ValueError, AttributeError) as e:
        return fail(f"catalog at {path} is not usable: {e}")

    cands = [m for m in models
             if isinstance(m, dict) and str(m.get("slug", "")).endswith("-" + tier)
             and m.get("visibility") == "list" and isinstance(m.get("priority"), int)]
    if not cands:
        return fail(f"no visible '{tier}' model in the catalog")
    if effort:
        cands = [m for m in cands
                 if effort in [l.get("effort") for l in m.get("supported_reasoning_levels") or [] if isinstance(l, dict)]]
        if not cands:
            return fail(f"no visible '{tier}' model lists effort '{effort}'")
    print(min(cands, key=lambda m: m["priority"])["slug"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
