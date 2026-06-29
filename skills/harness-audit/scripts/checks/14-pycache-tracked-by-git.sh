#!/usr/bin/env bash
# 14. PyCache tracked by git
if git -C "$REPO_ROOT" ls-files | grep -q '__pycache__\|\.pyc$'; then
  crit "__pycache__ or *.pyc tracked by git (should be .gitignore'd)"
fi

