#!/usr/bin/env bash
# test-mattpocock-root-resolver.sh — direct unit tests for
# scripts/_lib/mattpocock-root.sh's resolve_mattpocock_root (#92/T13). The
# two real call sites (hooks/session/doctrine-bootstrap.sh's preflight,
# skills/harness-audit/scripts/checks/51-mattpocock-integration-refs.sh) are
# covered at the integration level by tests/hooks/test-session-stop.sh and
# tests/skills/harness-audit/test-harness-audit.sh respectively; this file
# covers the resolver's own contract directly — multi-version highest-semver
# selection and the MH_MATT_CACHE env override, neither of which any single-
# version existing fixture exercises.
# Run standalone: bash tests/scripts/test-mattpocock-root-resolver.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/scripts/_lib/mattpocock-root.sh"

pass=0
fail=0
assert() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✅ $desc"; pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2; fail=$((fail + 1))
  fi
}

# make_ver_dir <cache_root> <version>: a version dir with one real SKILL.md,
# matching the resolver's own completeness probe.
make_ver_dir() {
  local d="$1/$2/skills/engineering/to-spec"
  mkdir -p "$d"
  printf '%s\n' '---
name: to-spec
description: fixture
---
body' > "$d/SKILL.md"
}

echo "=== resolve_mattpocock_root (scripts/_lib/mattpocock-root.sh) ==="
echo ""

CACHE=$(mktemp -d)
make_ver_dir "$CACHE" "1.0.0"
make_ver_dir "$CACHE" "1.2.3"
make_ver_dir "$CACHE" "1.10.0"
(
  MH_MATT_CACHE="$CACHE"
  export MH_MATT_CACHE
  # shellcheck source=../../scripts/_lib/mattpocock-root.sh
  . "$LIB"
  resolve_mattpocock_root
  rc=$?
  [[ "$rc" == "0" && "$MATT_VER" == "1.10.0" ]] && echo PASS || echo "FAIL rc=$rc ver=$MATT_VER"
) > /tmp/mattroot-out.$$ 2>&1
grep -q '^PASS$' /tmp/mattroot-out.$$ && ok=1 || ok=0
assert "picks the highest semver version dir among 1.0.0/1.2.3/1.10.0 (string-sort trap: 1.10.0 > 1.2.3)" "$ok"

CACHE2=$(mktemp -d)
make_ver_dir "$CACHE2" "9.9.9"
(
  MH_MATT_CACHE="$CACHE2"
  export MH_MATT_CACHE
  # shellcheck source=../../scripts/_lib/mattpocock-root.sh
  . "$LIB"
  resolve_mattpocock_root
  rc=$?
  [[ "$rc" == "0" && "$MATT_ROOT" == "$CACHE2/9.9.9" ]] && echo PASS || echo "FAIL rc=$rc root=$MATT_ROOT"
) > /tmp/mattroot-out2.$$ 2>&1
grep -q '^PASS$' /tmp/mattroot-out2.$$ && ok=1 || ok=0
assert "MH_MATT_CACHE env override is honored (resolves under the overridden root, not the real ~/.claude cache)" "$ok"

(
  MH_MATT_CACHE="/nonexistent-mattpocock-cache-$$"
  export MH_MATT_CACHE
  # shellcheck source=../../scripts/_lib/mattpocock-root.sh
  . "$LIB"
  resolve_mattpocock_root
  rc=$?
  [[ "$rc" != "0" && -z "$MATT_ROOT" && -z "$MATT_VER" ]] && echo PASS || echo "FAIL rc=$rc root=$MATT_ROOT ver=$MATT_VER"
) > /tmp/mattroot-out3.$$ 2>&1
grep -q '^PASS$' /tmp/mattroot-out3.$$ && ok=1 || ok=0
assert "returns 1 with MATT_ROOT/MATT_VER empty when the cache root doesn't exist" "$ok"

CACHE_HALF=$(mktemp -d)
mkdir -p "$CACHE_HALF/2.0.0/skills"  # version dir exists, skills/ is empty — interrupted extraction
(
  MH_MATT_CACHE="$CACHE_HALF"
  export MH_MATT_CACHE
  # shellcheck source=../../scripts/_lib/mattpocock-root.sh
  . "$LIB"
  resolve_mattpocock_root
  rc=$?
  [[ "$rc" != "0" && -z "$MATT_ROOT" ]] && echo PASS || echo "FAIL rc=$rc root=$MATT_ROOT"
) > /tmp/mattroot-out4.$$ 2>&1
grep -q '^PASS$' /tmp/mattroot-out4.$$ && ok=1 || ok=0
assert "rejects a half-extracted install: version dir present, no real SKILL.md under skills/ (acceptance criterion: 'rejects an incomplete cache')" "$ok"

rm -f /tmp/mattroot-out.$$ /tmp/mattroot-out2.$$ /tmp/mattroot-out3.$$ /tmp/mattroot-out4.$$
trash "$CACHE" "$CACHE2" "$CACHE_HALF" 2>/dev/null || true

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
