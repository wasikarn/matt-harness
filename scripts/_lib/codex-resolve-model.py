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
        if not effort:
            return fail("--effort needs a non-empty value")
        del args[i:i + 2]
    if len(args) != 1:
        return fail("usage: codex-resolve-model.py <tier> [--effort E]")
    tier = args[0].lower()
    if not tier:
        return fail("tier must not be empty")

    path = os.path.join(os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"), "models_cache.json")
    try:
        with open(path) as f:
            data = json.load(f)
    except OSError:
        return fail(f"no catalog at {path}")
    except ValueError as e:
        return fail(f"catalog at {path} is not usable: {e}")
    models = data.get("models") if isinstance(data, dict) else None
    if not isinstance(models, list):
        return fail(f"catalog at {path} has no 'models' list")

    def retiring(m):  # the catalog names a replacement: upgrade.model is a non-empty string
        u = m.get("upgrade")
        return isinstance(u, dict) and isinstance(u.get("model"), str) and u["model"] != ""

    # Skip a model with a non-int (or bool) priority, and one the catalog is retiring. The same
    # candidate rule as dotfiles' sync-profile-models.sh and model-catalog-drift.sh.
    cands = [m for m in models
             if isinstance(m, dict) and isinstance(m.get("slug"), str) and m["slug"].endswith("-" + tier)
             and m.get("visibility") == "list" and type(m.get("priority")) is int
             and not retiring(m)]
    if not cands:
        return fail(f"no visible '{tier}' model in the catalog")
    if effort:
        def lists_effort(m):
            levels = m.get("supported_reasoning_levels")
            return isinstance(levels, list) and effort in [l.get("effort") for l in levels if isinstance(l, dict)]
        cands = [m for m in cands if lists_effort(m)]
        if not cands:
            return fail(f"no visible '{tier}' model lists effort '{effort}'")
    print(min(cands, key=lambda m: m["priority"])["slug"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
