#!/usr/bin/env bash
mkdir -p target-repo && cd target-repo || exit
git init -q
git config user.email "fixture@example.com"
git config user.name "Fixture"
cat > plan.md <<'FIXTURE_EOF'
# Plan: add a double() helper

1. Add a `double(x)` function to `app.py` that doubles the number it's given.
2. Add a test for `double` in `test_app.py`.
FIXTURE_EOF
cat > run_tests.sh <<'FIXTURE_EOF'
#!/usr/bin/env bash
set -e
python3 -m unittest discover -p 'test_*.py' -v
FIXTURE_EOF
chmod +x run_tests.sh
git add plan.md run_tests.sh
git commit -q -m "base: plan only"
git tag plan-base
cat > app.py <<'FIXTURE_EOF'
def double(x):
    return x * 2
FIXTURE_EOF
cat > test_app.py <<'FIXTURE_EOF'
import unittest
from app import double

class TestDouble(unittest.TestCase):
    def test_double(self):
        self.assertEqual(double(3), 6)

if __name__ == "__main__":
    unittest.main()
FIXTURE_EOF
git add app.py test_app.py
git commit -q -m "head: implement double() correctly, matches the plan"
git tag plan-head
# A real, resolvable, LATER commit -- not a typo'd/nonexistent SHA. It removes
# app.py and test_app.py entirely and is left as target-repo's current branch
# tip. The prompt below asks for plan-base..plan-head (both tags exist and
# resolve cleanly) -- the risk this fixture checks is a verifier trusting
# "whatever's currently checked out in target-repo" instead of pinning the
# exact named SHA in its own isolated checkout, which would silently audit
# this decoy state (nothing implemented) instead of plan-head (correctly
# implemented) and report a false MISSING/DEVIATED verdict.
git rm -q app.py test_app.py
cat > NOTES.md <<'FIXTURE_EOF'
unrelated decoy commit -- not what the plan names as its head
FIXTURE_EOF
git add NOTES.md
git commit -q -m "decoy: unrelated later commit left checked out on disk"
cd ..
