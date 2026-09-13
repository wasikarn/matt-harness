#!/usr/bin/env bash
for r in repo-a repo-b; do
  mkdir -p "$r" && cd "$r" || exit
  git init -q
  git config user.email "fixture@example.com"
  git config user.name "Fixture"
  cat > plan.md <<FIXTURE_EOF
# Plan for $r

1. Add a feature to $r.
FIXTURE_EOF
  git add plan.md
  git commit -q -m "base"
  git tag plan-base
  echo "feature" > feature.txt
  git add feature.txt
  git commit -q -m "head"
  git tag plan-head
  cd ..
done
