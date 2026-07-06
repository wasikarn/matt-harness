#!/usr/bin/env bash
# Bisects a test suite to find which test file creates an unwanted filesystem/state
# artifact (leaked temp file, stray .git dir, leftover DB row) that pollutes tests
# run after it.
#
# Usage:
#   bash find-polluter.sh <path_to_check> <test_file_glob> [test_command]
#
# Example:
#   bash find-polluter.sh .git 'src/**/*.test.ts'
#   bash find-polluter.sh /tmp/leaked.db 'tests/*.py' pytest
#
# test_command defaults to an auto-detected runner based on project marker files
# in the current directory (npm test / cargo test / go test / flutter test / pytest).
# Pass one explicitly to override.

set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <path_to_check> <test_file_glob> [test_command]" >&2
  exit 1
fi

POLLUTION_CHECK="$1"
TEST_PATTERN="$2"

detect_runner() {
  if [ -f package.json ]; then echo "npm test --"
  elif [ -f Cargo.toml ]; then echo "cargo test"
  elif [ -f go.mod ]; then echo "go test"
  elif [ -f pubspec.yaml ]; then echo "flutter test"
  elif [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.py ]; then echo "pytest"
  else
    echo "No test_command given and no project marker recognized (package.json/Cargo.toml/go.mod/pubspec.yaml/pyproject.toml)." >&2
    exit 1
  fi
}

TEST_CMD="${3:-$(detect_runner)}"

# find -path matches against "./..." — anchor the glob so a plain "tests/*.sh" pattern still matches.
case "$TEST_PATTERN" in
  ./*) FIND_PATTERN="$TEST_PATTERN" ;;
  *) FIND_PATTERN="./$TEST_PATTERN" ;;
esac

mapfile -t TEST_FILES < <(find . -path "$FIND_PATTERN" | sort)
TOTAL=${#TEST_FILES[@]}

if [ "$TOTAL" -eq 0 ]; then
  echo "No test files matched: $TEST_PATTERN" >&2
  exit 1
fi

echo "Searching for test that creates: $POLLUTION_CHECK"
echo "Test pattern: $TEST_PATTERN ($TOTAL files) — runner: $TEST_CMD"
echo

COUNT=0
for TEST_FILE in "${TEST_FILES[@]}"; do
  COUNT=$((COUNT + 1))

  if [ -e "$POLLUTION_CHECK" ]; then
    echo "Pollution already exists before test $COUNT/$TOTAL — skipping: $TEST_FILE"
    continue
  fi

  echo "[$COUNT/$TOTAL] Testing: $TEST_FILE"
  # TEST_CMD intentionally splits into args here (e.g. "npm test --")
  # shellcheck disable=SC2086
  $TEST_CMD "$TEST_FILE" > /dev/null 2>&1 || true

  if [ -e "$POLLUTION_CHECK" ]; then
    echo
    echo "FOUND POLLUTER"
    echo "  Test: $TEST_FILE"
    echo "  Created: $POLLUTION_CHECK"
    ls -la "$POLLUTION_CHECK"
    echo
    echo "To investigate: $TEST_CMD $TEST_FILE"
    exit 1
  fi
done

echo
echo "No polluter found — all tests clean."
