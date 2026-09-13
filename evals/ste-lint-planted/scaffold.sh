#!/usr/bin/env bash
cat > notes.md <<'FIXTURE_EOF'
# Deployment notes

The deployment pipeline builds the container image, runs the full test suite against a staging cluster, and then promotes the same image to production once every check reports a clean result.

Do not skip the smoke test; a failed smoke test blocks the release.
FIXTURE_EOF
