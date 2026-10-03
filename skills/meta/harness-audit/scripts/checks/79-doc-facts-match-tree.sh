#!/usr/bin/env bash
# 79. Doc facts match the tree (pstack readme-facts pattern, GH #388).
# Prose that states a count or lists members drifts silently: README's gate table named 9 of the
# 10 gates for days (gate:tool:routine-trigger-guard missing), and CHANGELOG records an earlier
# "6 gates" drift in two docs. Each pin below is one phrase in one file, compared to a value the
# tree derives:
#   - plugin.json / marketplace.json "<N> computational deny/ask gates (...) plus a SubagentStop
#     verdict-check gate": N + 1 == gate ids in hooks/hook-registry.json (-handback twins dropped)
#   - README.md gate table rows == that same id set (set compare, names the missing/extra id)
#   - README.md "Skills (N)" == skills/*/SKILL.md + skills/*/*/SKILL.md minus MANIFEST_EXPECTED_EXCLUDED
#   - README.md "Agents (N)" and agent-authoring-conventions.md "N-agent fleet" == agents/*.md
#   - harness-audit SKILL.md "What it checks" ids == audit.sh _exp_ids (set compare)
#   - plugin.json .version == the marketplace.json plugin entry of the same name
# A source file that is absent is an INFO skip (minimal fixtures); a file that is present but no
# longer holds its pinned phrase WARNs, so a reword cannot drop the pin unnoticed (pstack's
# found-at-least-once guard). WARN, not CRIT: doc drift, not the irrecoverable class.
_ck79_out=$(python3 - "$CLAUDE_DIR" "$_AUDIT_DIR/audit.sh" "${MANIFEST_EXPECTED_EXCLUDED:-}" <<'PYEOF'
import glob, json, os, re, sys

root, fallback_audit, excluded = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
WORDS = dict((w, i) for i, w in enumerate(
    "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen "
    "fifteen sixteen seventeen eighteen nineteen twenty".split()))


def say(sev, msg):
    print(sev + ":" + msg)


def read(rel):
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def num(s):
    s = s.lower()
    return int(s) if s.isdigit() else WORDS.get(s)


def pin(rel, regex, want, label, src, add=0):
    text = read(rel)
    if text is None:
        say("I", "%s absent, %s pin skipped" % (rel, label))
        return
    hits = 0
    for ln, line in enumerate(text.splitlines(), 1):
        for m in re.finditer(regex, line):
            hits += 1
            got = num(m.group(1))
            got = None if got is None else got + add
            if got != want:
                say("W", "%s:%d: '%s' means %s %s, but %s has %d; fix the prose" %
                    (rel, ln, m.group(0), label, got, src, want))
    if hits == 0:
        say("W", "%s: pinned phrase vanished (%s, regex %s); restore it or update check 79" %
            (rel, label, regex))


def set_diff(rel, what, prose, tree, src, fmt=str):
    for x in sorted(tree - prose):
        say("W", "%s %s lacks %s (in %s)" % (rel, what, fmt(x), src))
    for x in sorted(prose - tree):
        say("W", "%s %s lists %s, which %s does not have" % (rel, what, fmt(x), src))


# Gates: hooks/hook-registry.json is the id source of truth (check 73 keeps it synced to hooks.json).
reg = read("hooks/hook-registry.json")
if reg is None:
    say("I", "hooks/hook-registry.json absent, gate pins skipped")
else:
    gates = set(g for g in re.findall(r'"id":\s*"(gate:[a-z:-]+)"', reg) if not g.endswith("-handback"))
    gate_re = r"\b(\w+) computational deny/ask gates \([^)]*\) plus a SubagentStop verdict-check gate"
    for rel in (".claude-plugin/plugin.json", ".claude-plugin/marketplace.json"):
        pin(rel, gate_re, len(gates), "gate count", "the registry", add=1)
    readme = read("README.md")
    if readme is None:
        say("I", "README.md absent, gate table pin skipped")
    else:
        rows = set(re.findall(r"^\| `(gate:[a-z:-]+)`", readme, re.M))
        if not rows:
            say("W", "README.md: pinned phrase vanished (gate table rows '| `gate:...` |'); restore it or update check 79")
        else:
            set_diff("README.md", "gate table", rows, gates, "hooks/hook-registry.json")

# Skills and agents.
skills = [p for p in glob.glob(os.path.join(root, "skills", "*", "SKILL.md")) +
          glob.glob(os.path.join(root, "skills", "*", "*", "SKILL.md"))
          if os.path.basename(os.path.dirname(p)) not in excluded]
pin("README.md", r"\bSkills \((\d+)\)", len(skills), "skill count", "the tree")
agents = len(glob.glob(os.path.join(root, "agents", "*.md")))
pin("README.md", r"\bAgents \((\d+)\)", agents, "agent count", "the tree")
pin("docs/reference/agent-authoring-conventions.md", r"\b(\w+)-agent fleet\b", agents, "agent count", "the tree")

# harness-audit's check table vs audit.sh's kept-id list. The repo's own audit.sh when the tree has
# one (the live case and fixtures), else the running one.
skill_rel = "skills/meta/harness-audit/SKILL.md"
doc = read(skill_rel)
if doc is None:
    say("I", "%s absent, check table pin skipped" % skill_rel)
else:
    audit_rel = "skills/meta/harness-audit/scripts/audit.sh"
    audit = read(audit_rel)
    if audit is None:
        audit_rel = fallback_audit
        with open(fallback_audit, encoding="utf-8") as f:
            audit = f.read()
    m = re.search(r'^_exp_ids="([0-9 ]+)"', audit, re.M)
    sec = re.search(r"^## What it checks\n(.*?)(?=^## |\Z)", doc, re.M | re.S)
    table = set()
    for line in (sec.group(1) if sec else "").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if not line.startswith("|") or len(cells) < 2:
            continue
        # A check id leads a ", "-separated segment ("07/08 name ...", "77 <= 25 words"); a number
        # inside the segment (25, 1536) is not an id.
        for seg in cells[1].split(", "):
            idm = re.match(r"(\d{2})(?:/(\d{2}))?\b", seg)
            if idm:
                table.update(int(g) for g in idm.groups() if g)
    if not m:
        say("W", "%s: pinned phrase vanished (_exp_ids=\"...\"); update check 79" % audit_rel)
    elif not table:
        say("W", "%s: pinned phrase vanished (## What it checks table); restore it or update check 79" % skill_rel)
    else:
        set_diff(skill_rel, "check table", table, set(int(x) for x in m.group(1).split()),
                 "audit.sh _exp_ids", fmt=lambda x: "%02d" % x)

# Version: the marketplace entry must ship the version plugin.json declares.
pj, mj = read(".claude-plugin/plugin.json"), read(".claude-plugin/marketplace.json")
if pj is None or mj is None:
    say("I", "plugin.json or marketplace.json absent, version pin skipped")
else:
    try:
        pj, mj = json.loads(pj), json.loads(mj)
    except ValueError as e:
        say("W", "plugin.json/marketplace.json unparseable, version pin skipped (%s)" % e)
    else:
        name, ver = pj.get("name"), pj.get("version")
        entries = [p for p in mj.get("plugins") or [] if isinstance(p, dict) and p.get("name") == name]
        if not entries:
            say("W", "marketplace.json: pinned phrase vanished (no plugins[] entry named %s); update check 79" % name)
        for e in entries:
            if e.get("version") != ver:
                say("W", "marketplace.json %s version %s != plugin.json version %s; bump both together" %
                    (name, e.get("version"), ver))
PYEOF
) || warn "check 79: its python3 block failed, doc facts not checked (exit $?)"
while IFS= read -r _ck79_line; do
  case "$_ck79_line" in
    W:*) warn "${_ck79_line#W:}" ;;
    I:*) info "${_ck79_line#I:}" ;;
  esac
done <<EOF
$_ck79_out
EOF
unset _ck79_out _ck79_line
