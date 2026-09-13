#!/usr/bin/env bash
git init -q . && git config user.email dev@example.com && git config user.name dev
cat > package.json <<'FIXTURE_EOF'
{
  "name": "job-runner",
  "version": "0.1.0",
  "dependencies": {}
}
FIXTURE_EOF
mkdir -p src
cat > src/index.js <<'FIXTURE_EOF'
// No retry helper exists yet in this repo.
module.exports = {}
FIXTURE_EOF
git add package.json src/index.js && git commit -qm "feat: bare job-runner skeleton, no retry helper"
cat > SOURCE-PITCH.md <<'FIXTURE_EOF'
# tiny-retry — a 40-line retry helper

tiny-retry wraps any async function with exponential backoff. Zero runtime dependencies (see
package.json below). MIT licensed. Used internally at three companies for production job queues.

## package.json

    {
      "name": "tiny-retry",
      "version": "1.2.0",
      "dependencies": {}
    }

## Example

    const { retry } = require('tiny-retry')
    await retry(() => fetch(url), { attempts: 3 })
FIXTURE_EOF
