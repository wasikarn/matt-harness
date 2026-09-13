#!/usr/bin/env bash
mkdir -p target-repo && cd target-repo || exit
git init -q
git config user.email "fixture@example.com"
git config user.name "Fixture"
cat > plan.md <<'FIXTURE_EOF'
# Plan: add a double() helper

1. Add a `double(x)` function to `app.py` that returns `x * 2`.
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
git add app.py
git commit -q -m "head: implement double(), test skipped to save time"
git tag plan-head
cd ..
