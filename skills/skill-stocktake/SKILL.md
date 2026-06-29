---
name: skill-stocktake
description: Audit installed skills for quality; supports Quick Scan (changed only) and Full Stocktake modes.
---

# Skill Stocktake

Audit your installed skills for quality, coverage, and usage. Choose Quick Scan or Full Stocktake.

## Quick Scan (default for regular check-ins)

Run when you want to review only skills that have changed since the last evaluation.

**Step 1 — Check for existing results**

```bash
RESULTS_JSON="$HOME/.local/share/kbg/skill-stocktake/results.json"
if [[ -f "$RESULTS_JSON" ]]; then
  cat "$RESULTS_JSON" | jq '{evaluated_at, skill_count: (.skills | length), mode}'
fi
```

**Step 2 — Find changed skills**

```bash
SCRIPTS_DIR="${CLAUDE_PLUGIN_ROOT}/skills/skill-stocktake/scripts"
bash "$SCRIPTS_DIR/quick-diff.sh" "$HOME/.local/share/kbg/skill-stocktake/results.json"
```

If output is `[]`, skills are unchanged — report "All skills up to date."

**Step 3 — Evaluate changed skills**

For each changed skill path returned by quick-diff.sh, read the SKILL.md and evaluate per the Full Stocktake criteria below. Batch in groups of ~20.

**Step 4 — Save updated results**

```bash
echo "$EVAL_JSON" | bash "$SCRIPTS_DIR/save-results.sh" "$HOME/.local/share/kbg/skill-stocktake/results.json"
```

## Full Stocktake

Run when results.json doesn't exist or the user explicitly requests a full audit.

**Phase 1 — Scan**

```bash
SCRIPTS_DIR="${CLAUDE_PLUGIN_ROOT}/skills/skill-stocktake/scripts"
mkdir -p "$HOME/.local/share/kbg/skill-stocktake"
bash "$SCRIPTS_DIR/scan.sh" | tee /tmp/stocktake-scan.json | jq '.scan_summary'
```

**Phase 2 — Agent evaluation (batch ~20)**

For each skill in `.skills[]`, evaluate:

| Criterion | What to check |
|-----------|---------------|
| Clarity | Is the description ≤25 words and accurate? |
| Completeness | Does the SKILL.md body explain when and how to use it? |
| Freshness | When was it last modified? Is it still relevant? |
| Usage | `use_7d` and `use_30d` counts (0 = possibly unused) |
| Duplication | Does another skill overlap significantly? |

Rate each skill: `keep` / `improve` / `deprecate`.

**Phase 3 — Summary table**

Output a markdown table:

| Skill | Rating | Usage (7d/30d) | Issue |
|-------|--------|----------------|-------|
| … | keep | 3/12 | — |
| … | improve | 0/0 | description too long |

**Phase 4 — Consolidation**

For any `improve` or `deprecate` items:
- `improve`: propose updated description or SKILL.md additions
- `deprecate`: confirm with user before removal

Save final results:

```bash
echo "$FULL_EVAL_JSON" | bash "$SCRIPTS_DIR/save-results.sh" "$HOME/.local/share/kbg/skill-stocktake/results.json"
```
