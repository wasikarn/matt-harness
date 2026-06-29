# 28. Frontmatter YAML validity — strict-parse every agent/skill/command
# frontmatter. The grep-based fm_get reads `name:` even out of a malformed
# block, so a broken double-quoted description (a stray `"` mid-string) or an
# unquoted `Key: value` colon passes every other check here yet makes Claude
# Code silently DROP the agent/skill from the runtime registry ("agent type
# 'X' not found"). A load-breaking defect = CRITICAL (pre-commit blocks it).
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  # One python pass over all frontmatters; emits "<path>\t<error>" per broken
  # file. Process substitution (not a pipe) keeps crit() in the current shell
  # so the count propagates — same reason as #13.
  while IFS=$'\t' read -r badf err; do
    [ -n "$badf" ] || continue
    crit "frontmatter: '${badf#"$REPO_ROOT"/}' has invalid YAML — Claude Code won't load it: $err"
  done < <(python3 - "$CLAUDE_DIR" <<'PY'
import sys, os, glob
try:
    import yaml
except Exception:
    sys.exit(0)
root = sys.argv[1]
def frontmatter(path):
    t = open(path, encoding='utf-8').read()
    if not t.startswith('---'):
        return None
    end = t.find('\n---', 3)
    return t[3:end] if end != -1 else None
files = (sorted(glob.glob(os.path.join(root, 'agents', '*.md')))
         + sorted(glob.glob(os.path.join(root, 'commands', '*.md')))
         + sorted(glob.glob(os.path.join(root, 'skills', '*', 'SKILL.md'))))
for f in files:
    # skip _-prefixed scaffolds (e.g. skills/_template) — not real fleet
    if os.path.basename(f).startswith('_') or os.path.basename(os.path.dirname(f)).startswith('_'):
        continue
    fm = frontmatter(f)
    if fm is None:
        continue
    try:
        yaml.safe_load(fm)
    except yaml.YAMLError as e:
        print(f"{f}\t{str(e).splitlines()[0].strip()}")
PY
)
else
  # Fail loud about the skip (Rule 12) — a silently-skipped validator is the
  # exact failure mode this check exists to catch.
  warn "frontmatter YAML validity check skipped — python3+PyYAML unavailable"
fi

