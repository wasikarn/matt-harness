# 37. DOMAINS.md `## Path → Context` ≡ orchestrator-nudge.sh PATH_PATTERNS.
# Both encode the SAME path→routing-label map; DOMAINS.md and the hook's "SYNC:"
# comment each assert they stay in lockstep, but nothing enforced it — and they
# HAD drifted (the entire Integration group + several role assignments were
# missing from the doc). The hook is the executor (source of truth); this check
# verifies the doc table mirrors it token-for-token. Same class as #12/#16 (doc
# must track code) → WARN. Deterministic set-equality on `token|Label` pairs.
# Hermetic: skips if either file is absent. The label whitelist anchors the
# hook-side grep so only real PATH_PATTERNS pair lines match (no block parsing).
DOMAINS_MD="$CLAUDE_DIR/DOMAINS.md"
NUDGE_SH="$CLAUDE_DIR/hooks/advisory/orchestrator-nudge.sh"
if [ -f "$DOMAINS_MD" ] && [ -f "$NUDGE_SH" ]; then
  _labels='Execution|Implementation|Orchestration|Quality|Communication|Emergency|Integration|doctrine|infra|docs'
  _pp=$(grep -E "^[A-Za-z._][^| ]*\|(${_labels})\$" "$NUDGE_SH" 2>/dev/null | sort -u)
  _dm=$(awk -F'|' '/^## Path . Context/{f=1;next} f&&/^## /{exit} f&&/^\|/&&/`/{
    label=$3; gsub(/^[ \t]+|[ \t]+$/,"",label);
    n=split($2,a,"`");
    for(i=2;i<=n;i+=2){t=a[i]; gsub(/^[ \t]+|[ \t]+$/,"",t); if(t!="") print t"|"label}
  }' "$DOMAINS_MD" 2>/dev/null | sort -u)
  if [ "$_pp" != "$_dm" ]; then
    # `|| true`: diff exits 1 on differences (always, in this branch) — without
    # the guard `set -euo pipefail` aborts before the warn fires (same latent
    # bug fixed in #41). Was dormant: this seam is normally aligned.
    _d=$(diff <(printf '%s\n' "$_pp") <(printf '%s\n' "$_dm") | tr '\n' ' ' | cut -c1-280 || true)
    warn "DOMAINS.md '## Path → Context' out of sync with orchestrator-nudge.sh PATH_PATTERNS (hook is source of truth) — diff (< hook, > doc): $_d"
  fi
fi

