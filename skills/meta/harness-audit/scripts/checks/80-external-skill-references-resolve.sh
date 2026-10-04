#!/usr/bin/env bash
# 80. External skill references resolve (GH #394, pstack-claude adoption audit 2026-10-03).
# Prose names skills as `<namespace>:<name>`; a rename or a retirement upstream leaves the name
# dangling with nothing to flag it (mattpocock-skills:writing-fragments and
# git-guardrails-claude-code sit on disk in the plugin cache but outside its plugin.json skills[],
# so Claude Code never loads them). Each reference resolves per namespace:
#   - mh:<n>                -> this tree: skills/**/<n>/SKILL.md or agents/<n>.md (the cache lags
#                              the tree; check 75 owns shipped-vs-excluded)
#   - mattpocock-skills:<n> -> newest cached version: plugin.json skills[] when present (an entry
#   - codex:<n>                holding a SKILL.md is itself, else its direct children, as check 75's
#                              loads()), else skills/<n>/; plus commands/<n>.md and agents/<n>.md
# A namespace with no plugin cache (CI) is an INFO skip. Scope is prose: *.md in README.md,
# CLAUDE.md, CONTEXT.md, AGENTS.md, docs/ (minus the frozen research/, plans/, post-mortems/ and
# any `status: deprecated` ADR), skills/, agents/. Code and tests name hook ids (mh:gate:...) and
# fake tokens by design. A token followed by `:` is a hook id, not a reference. WARN: doc rot.
_ck80_out=$(python3 - "$CLAUDE_DIR" "$HOME/.claude/plugins/cache" <<'PYEOF'
import glob, json, os, re, sys

root, cache = sys.argv[1], sys.argv[2]
PLUGINS = {"mattpocock-skills": "mattpocock-skills", "codex": "codex"}
FROZEN = ("docs/research/", "docs/plans/", "docs/post-mortems/")
REF = re.compile(r"(?<![\w.-])(mattpocock-skills|codex|mh):([a-z][a-z0-9-]*[a-z0-9])(?![\w:-])")


def vkey(path):
    return [int(x) if x.isdigit() else -1 for x in re.split(r"[.-]", os.path.basename(path))]


def plugin_names(proot):
    names = set()
    skills = None
    try:
        with open(os.path.join(proot, ".claude-plugin", "plugin.json")) as f:
            skills = json.load(f).get("skills")
    except (OSError, ValueError, AttributeError):
        pass
    if isinstance(skills, list):
        for e in skills:
            if not isinstance(e, str):
                continue
            d = os.path.join(proot, e.lstrip("./").rstrip("/"))
            if os.path.isfile(os.path.join(d, "SKILL.md")):
                names.add(os.path.basename(d))
            else:
                names.update(os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(d, "*", "SKILL.md")))
    else:
        names.update(os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(proot, "skills", "*", "SKILL.md")))
    for kind in ("commands", "agents"):
        names.update(os.path.basename(p)[:-3] for p in glob.glob(os.path.join(proot, kind, "*.md")))
    return names


known = {}
mh = set(os.path.basename(p)[:-3] for p in glob.glob(os.path.join(root, "agents", "*.md")))
for d, dirs, files in os.walk(os.path.join(root, "skills")):
    dirs[:] = [x for x in dirs if not x.startswith("_")]
    if "SKILL.md" in files:
        mh.add(os.path.basename(d))
known["mh"] = mh
for ns, plugin in PLUGINS.items():
    vers = [p for p in glob.glob(os.path.join(cache, "*", plugin, "*")) if os.path.isdir(p)]
    if not vers:
        print("I:%s plugin not installed (no %s/*/%s/<version>/), its references not checked" % (ns, cache, plugin))
        continue
    known[ns] = plugin_names(max(vers, key=vkey))

files = [os.path.join(root, f) for f in ("README.md", "CLAUDE.md", "CONTEXT.md", "AGENTS.md")]
for top in ("docs", "skills", "agents"):
    for d, dirs, names in os.walk(os.path.join(root, top)):
        files.extend(os.path.join(d, n) for n in names if n.endswith(".md"))
for path in sorted(files):
    rel = os.path.relpath(path, root)
    if rel.startswith(FROZEN) or not os.path.isfile(path):
        continue
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    if rel.startswith("docs/adr/") and re.match(r"---\n(?:(?!---\n).*\n)*?status:\s*deprecated\b", text):
        continue
    seen = set()
    for ln, line in enumerate(text.splitlines(), 1):
        for m in REF.finditer(line):
            ns, name = m.groups()
            if ns in known and name not in known[ns] and (ln, m.group(0)) not in seen:
                seen.add((ln, m.group(0)))
                print("W:%s:%d: '%s' does not resolve (no such %s skill, command or agent); reword or fix the name" %
                      (rel, ln, m.group(0), ns))
PYEOF
) || warn "check 80: its python3 block failed, external skill references not checked (exit $?)"
while IFS= read -r _ck80_line; do
  case "$_ck80_line" in
    W:*) warn "${_ck80_line#W:}" ;;
    I:*) info "${_ck80_line#I:}" ;;
  esac
done <<EOF
$_ck80_out
EOF
unset _ck80_out _ck80_line
