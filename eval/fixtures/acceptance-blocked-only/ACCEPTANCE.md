# Blocked-only acceptance fixture

Regression fixture for `run-acceptance.py` exit-code contract. The single
criterion below contains a backticked destructive command that the runner's
safety deny list blocks. With zero failed criteria and one blocked criterion,
the runner must return exit code 4 (not 0, not 1) so BLOCK cannot masquerade as
PASS on the operator scoreboard.

## Criteria

- [x] `git push origin main` → blocked by safety deny list, produces status "blocked".
