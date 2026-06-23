# 38. dismiss-stale.md Q3 mirror ≡ notify-sensor-staleness.sh gate. The command
# duplicates the hook's is_stale/is_must_fire_stale/role-classification gate AND
# the Q3 trigger thresholds verbatim (a SYNC-WITH comment is the only seam). It
# DRIFTED once: the hook's null-branch was fixed to `return s.get("observable",
# True)` while the command kept `return True`, so the two computed different stale
# sets and the dismissal hash never matched (a silent no-op the operator hit on
# /dismiss-stale). This asserts the full set of load-bearing gate lines — both the
# classification (is_stale/must_fire) AND the trigger thresholds (1 enforcement /
# ≥3 advisory / ≥1 must_fire) — appear in BOTH files (whitespace-normalized,
# substring). WARN.
DSM="$CLAUDE_DIR/commands/dismiss-stale.md"
NSS="$CLAUDE_DIR/hooks/maintenance/notify-sensor-staleness.sh"
if [ -f "$DSM" ] && [ -f "$NSS" ]; then
  _nss_n=$(tr -s ' \t' ' ' < "$NSS")
  _dsm_n=$(tr -s ' \t' ' ' < "$DSM")
  while IFS= read -r _sig; do
    [ -n "$_sig" ] || continue
    if printf '%s' "$_nss_n" | grep -qF "$_sig" && ! printf '%s' "$_dsm_n" | grep -qF "$_sig"; then
      warn "dismiss-stale.md Q3 mirror missing gate line present in notify-sensor-staleness.sh: '$_sig' — the two MUST stay in sync (commands/dismiss-stale.md SYNC-WITH seam)"
    fi
  done <<'SIGS'
return s.get("observable", True)
return ds > thr
return ds is not None and ds >= 1
enforcement_roles = {"computational-FF", "computational-FB"}
advisory_roles = {"inferential-FF", "inferential-FB"}
len(enforcement_stale) >= 1
or len(advisory_stale) >= 3
or len(must_fire_stale) >= 1
SIGS
fi

