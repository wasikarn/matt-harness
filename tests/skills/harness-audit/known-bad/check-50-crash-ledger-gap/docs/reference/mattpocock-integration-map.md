# mattpocock integration map — fixture (crash-ledger-gap)

`foo` is promoted by the fixture cache's plugin.json but has no row here at all — the exact
shape that used to crash sub-check C's `_row=$(grep ... | head -1)` under `set -euo pipefail`
before the `|| true` fix.

| skill | invocation | kbg touchpoint |
|---|---|---|
| bar | user | fixture route (type `/mattpocock-skills:bar`) |
