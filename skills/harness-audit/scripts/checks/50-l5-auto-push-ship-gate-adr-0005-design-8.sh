# 50. L5 auto-push ship-gate (CLAUDE.md §The operating model (was L5 auto-push, retired), design §8.5, #35). With the human out of the
# push loop, the in-plugin ship-gate (folded into push-gate.sh as the L5 leg) must
# default to an EMPTY allowlist (an un-configured install pushes NOWHERE), deny on
# cross-remote host+org divergence, AND require a green gauntlet (a recent l3_cycle
# green event) — the model never authorizes the ship. Positive assertions over the
# push-gate's L5 leg (CRIT UNLESS each holds — design §8.5 blocker: same commit as
# the gate; test injects a regression + asserts the CRIT).
# RETIRED 2026-06-25 — L5 ship-gate leg removed with push-gate.sh (CLAUDE.md §The operating model (was L5 auto-push, retired) addendum; CLAUDE.md §The operating model (was L4 self-launch, retired) Gate-2 + CLAUDE.md §The operating model (was L5 auto-push, retired) L5 RETIRED, ECC-aligned scoped-denial retirement). The allowlist/empty-default/get-url/green/membership contract checks are retired with the gate. (This line intentionally does NOT start with `# 50.` — that would be a second fragment header and trip the check-fragment header-mismatch guard. The single `# 50.` header above is the one ncheck greps.)
info "audit #50: RETIRED 2026-06-25 — L5 ship-gate leg removed with push-gate.sh (CLAUDE.md §The operating model (was L5 auto-push, retired) addendum)" 2>/dev/null || true
# NOTE: no `exit 0` here — audit checks are SOURCED by audit.sh, so `exit 0` would
# terminate the whole audit mid-run (skipping #52 + the Summary block and forcing
# rc=0 over prior CRITs). A retired check records its INFO and returns; audit.sh
# continues to the next check and emits its Summary with the correct rc.

