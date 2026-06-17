#!/usr/bin/env bash
# Fixture hook for harness-audit tests. Not wired in settings.json or
# hooks.json — exists only to prove F1 fires on a non-symlinked, non-plugin
# delivered hook. Don't symlink or wire this anywhere — it's a test fixture.
exit 0
