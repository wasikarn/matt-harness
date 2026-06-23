# 31. Schema-rot detector — round-2 (2026-06-11) found that the pre-emit
# validator at scripts/review-pr-journal-pre-emit-validator.py is scoped
# to the review-pr journaler's enum regexes only. No general detector
# existed for: skill I/O contract drift, plugin.json version drift,
# settings.json permission drift, or hooks.json schema drift. The
# decay-cadence is the unifying ritual but lives in
# docs/harness-decay-cadence.md as a doc, not as a check. This check
# runs 4 sub-checks; only the hooks.json sub-check is STRUCTURAL (crit);
# the rest are ADVISORY (info). The check surfaces drift; the human acts.
#
# Sub-check 31.1 — Skill SKILL.md section presence: emit a SINGLE info per
# skill listing every missing canonical section. This keeps noise at
# 1-per-skill (not N-per-skill) and still catches drift: a skill that
# USED to have the sections but no longer does will show up in audit
# output as a stable, actionable bullet. Sections are: ## Input
# Contract, ## Output Format, ## Failure Modes. The check is hermetic —
# it only inspects the file itself, not the references the contract
# might name (URLs / external sources can't be checked from here).
# Sub-check 31.2 — plugin.json / marketplace.json: emit info if the
# `version` field is older than 30 days (hardcoded in _check_plugin_version
# below) AND has no sibling `last_reviewed:` / `last_reviewed_reason:`
# justification. Emit crit if the file does not parse as JSON or
# `version` is missing. Defense in depth: claude plugin validate
# already enforces the JSON shape, but a missing `version` is the
# specific failure mode that breaks the cache-resolver at audit.sh:73.
# Sub-check 31.3 — settings.json permission re-audit bookmark: per
# decay-cadence §Permission re-audit, the kbg-harness equivalent is
# a `## Permission re-audit` section with a `last_permission_review:
# YYYY-MM-DD` marker in `docs/harness-decay-cadence.md`. Emit info if
# the marker is older than 90 days (PERM_MAX_AGE, hardcoded;
# quarterly cadence). (The plugin.json `last_permission_review_sha`
# equivalent was named in the original doc-comment but never
# implemented — doc trimmed in round-2 audit reconcile 2026-06-12
# to match the actual check below; lines ~1008-1039.)
# Sub-check 31.4 — hooks.json schema: STRUCTURAL. Every `matcher` in the
# JSON must be a non-empty string, every `hooks[]` entry must have a
# `type` field, every `command` value must be non-empty. Emit crit on
# violation. A malformed hooks.json will cause Claude Code to fail to
# load hooks at runtime — a silent config-drift failure mode the rest
# of the audit cannot see.
if command -v python3 >/dev/null 2>&1; then
  # Run all 4 sub-checks in a single python invocation and dispatch each
  # TSV line to info / warn / crit. We use a here-doc via process
  # substitution so the bash helpers can keep their counters (subshells
  # would lose the increments).
  while IFS=$'\t' read -r kind payload extra; do
    [ -n "$kind" ] || continue
    case "$kind" in
      PLUGIN_PARSE_FAIL)     crit "schema-rot: $(basename "$payload" 2>/dev/null || echo "$payload") failed to parse as JSON" ;;
      PLUGIN_NO_VERSION)     crit "schema-rot: $(basename "$payload" 2>/dev/null || echo "$payload") has no 'version' field (cache-resolver will break)" ;;
      PLUGIN_STALE)          info "schema-rot: $payload — consider a version bump (30d cadence per decay-cadence)" ;;
      PERM_BOOKMARK_MISSING) info "schema-rot: $payload — add a 'last_permission_review:' marker (quarterly cadence per decay-cadence)" ;;
      PERM_BOOKMARK_BAD)     warn "schema-rot: permission re-audit marker date is unparseable: $payload" ;;
      PERM_BOOKMARK_STALE)   info "schema-rot: permission re-audit $payload" ;;
      HOOKS_PARSE_FAIL)      crit "schema-rot: hooks.json failed to parse: $payload" ;;
      HOOKS_SHAPE_FAIL)      crit "schema-rot: hooks.json — $payload" ;;
      HOOKS_SHAPE_WARN)      warn "schema-rot: hooks.json — $payload" ;;
    esac
  done < <(python3 - "$CLAUDE_DIR" "$REPO_ROOT" <<'PY' 2>/dev/null
import datetime as dt, json, os, re, sys
claude_dir, repo_root = sys.argv[1], sys.argv[2]
today = dt.date.today()

# 31.1 RETIRED 2026-06-16 — the "every SKILL.md must carry ## Input Contract /
# ## Output Format / ## Failure Modes" requirement was a self-referential blanket:
# a presence-only check (substring of three headings, never content) that 29/37
# skills satisfied with byte-identical boilerplate from an unreferenced generator
# (scripts/utils/add-canonical-sections.py, now deleted). Nothing functional read
# the sections beyond this check; it manufactured the schema-rot it claimed to
# police (same shape as the retired `type: command`). The real per-skill contract
# survives where a skill actually has one; it is no longer mandated fleet-wide.

# 31.2: plugin.json / marketplace.json version validity + cadence
# For plugin.json the top-level `version` is canonical. For
# marketplace.json the version lives in `plugins[].version` (the
# marketplace is a list of plugins, not a single plugin manifest).
PLUGIN_DIR = os.path.join(repo_root, ".claude-plugin")
def _check_plugin_version(p, version_value, reason):
    if not isinstance(version_value, str) or not version_value.strip():
        print(f"PLUGIN_NO_VERSION\t{os.path.basename(p)}")
        return
    try:
        mtime = dt.date.fromtimestamp(os.path.getmtime(p))
    except OSError:
        return
    age = (today - mtime).days
    if age > 30 and not reason:
        print(f"PLUGIN_STALE\t{os.path.basename(p)}\tversion={version_value}\tage_days={age}")
p_plugin = os.path.join(PLUGIN_DIR, "plugin.json")
if os.path.isfile(p_plugin):
    try:
        data = json.loads(open(p_plugin, encoding="utf-8", errors="replace").read())
    except (OSError, ValueError):
        print(f"PLUGIN_PARSE_FAIL\tplugin.json")
    else:
        if not isinstance(data, dict):
            print(f"PLUGIN_PARSE_FAIL\tplugin.json\t(not an object)")
        else:
            _check_plugin_version(
                p_plugin,
                data.get("version"),
                data.get("last_reviewed_reason") or "",
            )
p_market = os.path.join(PLUGIN_DIR, "marketplace.json")
if os.path.isfile(p_market):
    try:
        data = json.loads(open(p_market, encoding="utf-8", errors="replace").read())
    except (OSError, ValueError):
        print(f"PLUGIN_PARSE_FAIL\tmarketplace.json")
    else:
        if not isinstance(data, dict):
            print(f"PLUGIN_PARSE_FAIL\tmarketplace.json\t(not an object)")
        else:
            # marketplace.json: per the claude-code-marketplace.json
            # schema, `plugins[].version` is OPTIONAL — the actual
            # version lives in plugin.json. We only STALE-check the
            # marketplace file itself (its mtime is the real signal
            # that the marketplace hasn't been touched in 30d); we
            # do NOT crit-fire on missing version (that would be a
            # false positive on every marketplace that doesn't
            # duplicate the version field).
            try:
                mtime = dt.date.fromtimestamp(os.path.getmtime(p_market))
            except OSError:
                pass
            else:
                age = (today - mtime).days
                if age > 30:
                    print(f"PLUGIN_STALE\tmarketplace.json\ttop-level\tage_days={age}")

# 31.3: settings.json / decay-cadence permission re-audit bookmark
# decay-cadence lives at docs/harness-decay-cadence.md. Look in both
# possible locations (extracted kbg-harness vs. dotfiles checkout).
cadence_candidates = [
    os.path.join(repo_root, "docs", "harness-decay-cadence.md"),
    os.path.join(claude_dir, "docs", "harness-decay-cadence.md"),
]
cadence_path = next((p for p in cadence_candidates if os.path.isfile(p)), None)
PERM_MAX_AGE = 90
if cadence_path is None:
    print("PERM_BOOKMARK_MISSING\tdocs/harness-decay-cadence.md not found")
else:
    try:
        text = open(cadence_path, encoding="utf-8", errors="replace").read(65536)
    except OSError:
        text = ""
    # Marker shape: a `last_permission_review_sha: YYYY-MM-DD ...` line
    # (the `_sha` suffix is optional in the regex so older markers
    # without a SHA still get picked up).
    m = re.search(r"^[\s#/*-]*last_permission_review(?:_sha)?:\s*(\d{4}-\d{2}-\d{2})",
                  text, re.MULTILINE)
    if not m:
        print(f"PERM_BOOKMARK_MISSING\treview-marker not found in {os.path.relpath(cadence_path, repo_root)}")
    else:
        try:
            d = dt.date.fromisoformat(m.group(1))
        except ValueError:
            print(f"PERM_BOOKMARK_BAD\t{m.group(1)}")
        else:
            age = (today - d).days
            if age > PERM_MAX_AGE:
                print(f"PERM_BOOKMARK_STALE\treviewed {age} days ago (cadence: {PERM_MAX_AGE}d)")

# 31.4: hooks.json schema (STRUCTURAL, crit)
hooks_json_candidates = [
    os.path.join(repo_root, "hooks", "hooks.json"),
    os.path.join(claude_dir, "hooks", "hooks.json"),
]
hooks_path = next((p for p in hooks_json_candidates if os.path.isfile(p)), None)
if hooks_path is not None:
    try:
        data = json.loads(open(hooks_path, encoding="utf-8", errors="replace").read())
    except (OSError, ValueError) as e:
        print(f"HOOKS_PARSE_FAIL\t{e}")
    else:
        # Top-level shape: {"hooks": {"EventName": [{"matcher": "x", "hooks": [...]}, ...]}}
        hooks_root = data.get("hooks") if isinstance(data, dict) else None
        if not isinstance(hooks_root, dict):
            print("HOOKS_SHAPE_FAIL\tmissing top-level 'hooks' object")
        else:
            for event_name, groups in hooks_root.items():
                if not isinstance(groups, list):
                    print(f"HOOKS_SHAPE_FAIL\t{event_name}: not a list")
                    continue
                for gi, group in enumerate(groups):
                    if not isinstance(group, dict):
                        print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}]: not an object")
                        continue
                    # matcher is OPTIONAL in the spec. If present, must be a string
                    # (empty string is valid per vendor convention — empty matcher =
                    # "match all known sources", used for events with multi-source
                    # semantics like ConfigChange. See hooks/config-change-log.sh
                    # header for the rationale.) Refined after round-2 reconcile
                    # (2026-06-12): F2 check #31's "must be non-empty" was too
                    # strict and flagged the legitimate ConfigChange empty matcher.
                    matcher = group.get("matcher")
                    if matcher is not None and not isinstance(matcher, str):
                        print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].matcher: not a string")
                    inner = group.get("hooks")
                    if not isinstance(inner, list) or not inner:
                        print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks: missing or empty")
                        continue
                    for hi, h in enumerate(inner):
                        if not isinstance(h, dict):
                            print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}]: not an object")
                            continue
                        hook_type = h.get("type")
                        if not isinstance(hook_type, str) or not hook_type.strip():
                            print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].type: missing/empty")
                            continue
                        # Validate required fields per hook type (Claude Code hook schema).
                        if hook_type == "command":
                            if not isinstance(h.get("command"), str) or not h["command"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].command: missing/empty")
                        elif hook_type == "http":
                            if not isinstance(h.get("url"), str) or not h["url"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].url: missing/empty")
                        elif hook_type == "mcp":
                            if not isinstance(h.get("server"), str) or not h["server"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].server: missing/empty")
                            if not isinstance(h.get("tool"), str) or not h["tool"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].tool: missing/empty")
                        elif hook_type == "agent":
                            if not isinstance(h.get("agent"), str) or not h["agent"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].agent: missing/empty")
                        elif hook_type == "prompt":
                            if not isinstance(h.get("prompt"), str) or not h["prompt"].strip():
                                print(f"HOOKS_SHAPE_FAIL\t{event_name}[{gi}].hooks[{hi}].prompt: missing/empty")
                        else:
                            # Unknown type is not a hard failure today; emit a warning shape entry.
                            print(f"HOOKS_SHAPE_WARN\t{event_name}[{gi}].hooks[{hi}].type: unknown hook type '{hook_type}'")
PY
)
else
  warn "schema-rot check skipped — python3 unavailable"
fi

