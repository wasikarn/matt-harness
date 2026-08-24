# Fixture CLAUDE.md — check 51 manifest drift

Clean refs only: `mattpocock-skills:foo` resolves. The violation in this fixture lives in
the fake cache's plugin.json (object-form skills array the parser can't read) and the
ledger's duplicate row.
