#!/usr/bin/env bash
# 27. Test-honesty / tautology detector — static check that tests verify intent, not just shape.
# Catches "test that can't fail when behavior changes" by greppable patterns
# in test files only. Paired with claude/rules/test-honesty.md (write-time hint)
# and `/ship` Phase 5 TDD default (workflow gate).
while IFS= read -r f; do
  [ -e "$f" ] || continue
  rel="${f#$REPO_ROOT/}"
  # 27.1 — tautological assertion: assert True / assert False / assertEqual(x, x)
  if grep -nE 'assert[[:space:]]+(True|true|False|false)[[:space:]]*[),]' "$f" >/dev/null 2>&1; then
    crit "test-honesty: '$rel' has tautological assert True/False"
  fi
  # 27.2 — identity / repr assertion: type(x) is type(x), repr(x) == repr(x),
  # isinstance(x, type(x)). Passes regardless of behavior.
  if grep -nE '(type\(.*\)[[:space:]]+(is|==)[[:space:]]+type\(|repr\(.*\)[[:space:]]*==[[:space:]]*repr|isinstance\(.*,[[:space:]]*type\()' "$f" >/dev/null 2>&1; then
    warn "test-honesty: '$rel' asserts on identity/repr, not behavior"
  fi
  # 27.3 — placeholder test name: smoke / basic / works / sanity / simple / temp
  if grep -nE 'def[[:space:]]+test_(smoke|basic|works?|sanity|simple|temp|placeholder)\b' "$f" >/dev/null 2>&1; then
    warn "test-honesty: '$rel' has test_<placeholder> name (encode WHY, not WHAT)"
  fi
  # 27.4 — test function body is `pass` or `...` after def+optional docstring.
  # Grep for `def test_` line, then look 1-3 lines after for pass-only/...-only.
  if awk '
    /^def[[:space:]]+test_/ { hit=1; body=0; next }
    hit && /^[[:space:]]*$/ { next }
    hit && /^[[:space:]]*"""/ { in_doc=!in_doc; next }
    hit && /^[[:space:]]*("""|'"'"''"'"''')/ { in_doc=!in_doc; next }
    hit && !in_doc { body=1; if ($0 ~ /^[[:space:]]+(pass|\.\.\.)[[:space:]]*$/) { print FILENAME":"NR":"$0; exit 0 }; hit=0 }
    { hit=0 }
  ' "$f" | grep -q .; then
    warn "test-honesty: '$rel' has test_ function with pass/... body (no assertion)"
  fi
done < <(find "$REPO_ROOT" -type f \( \
    -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.test.jsx' -o \
    -name '*.spec.ts' -o -name '*.spec.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' -o \
    -name 'test_*.py' -o -name '*_test.py' \
  \) -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null || true)

