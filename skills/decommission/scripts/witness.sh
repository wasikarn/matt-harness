#!/usr/bin/env bash
# Unified witness module — ed25519-signed, namespace-scoped assertion manifests.
# Subcommands: init | sign | verify
# Namespaces: decommission (ABSENT_*) | assert-presence (PRESENT_*)
#
# Wire format is identical to the legacy 6-script shape: ssh-keygen -Y sign
# over a text manifest, ASCII-armored .sig next to it, allowed_signers line
# carries namespaces="<ns>". Existing signed files (pre-unification) verify
# unchanged.
set -euo pipefail

# ── namespace defaults ──────────────────────────────────────────────
# Each namespace bundles: ssh-keygen namespace string, file glob, required
# header labels, default grammar (absent|present), failure banner.
# SKILL.md invocations can omit --file-glob and get the namespace's default.
ns_defaults() {
  case "$1" in
    decommission)
      GLOB='.witness/*.txt'
      GRAMMAR='absent'
      HEADERS=('decommission witness:' 'decommissioned:' 'reason:' 'rollback:')
      BANNER='DECOMMISSION DRIFT'
      ;;
    assert-presence)
      GLOB='.witness/assert-presence-*.txt'
      GRAMMAR='present'
      HEADERS=('assert-presence witness:' 'asserted:' 'agent:' 'evidence:')
      BANNER='ASSERTION REGRESSION'
      ;;
    *)
      echo "unknown namespace: $1 (expected: decommission | assert-presence)" >&2
      exit 1
      ;;
  esac
}

# ── arg parsing ─────────────────────────────────────────────────────
cmd="${1:-}"
[ -z "$cmd" ] && { echo "usage: $0 {init|sign|verify} --namespace=<ns> [opts] [slug]" >&2; exit 1; }
shift

NS=""
GLOB_OVERRIDE=""
ALLOWED_OVERRIDE=""
SLUG=""
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --namespace=*)        NS="${1#--namespace=}" ;;
    --file-glob=*)        GLOB_OVERRIDE="${1#--file-glob=}" ;;
    --allowed-signers=*)  ALLOWED_OVERRIDE="${1#--allowed-signers=}" ;;
    --force)              FORCE=1 ;;
    -*)                   echo "unknown flag: $1" >&2; exit 1 ;;
    *)                    SLUG="$1" ;;
  esac
  shift
done

[ -z "$NS" ] && { echo "--namespace=<decommission|assert-presence> required" >&2; exit 1; }

ns_defaults "$NS"
GLOB="${GLOB_OVERRIDE:-$GLOB}"
KEY="$HOME/.ssh/witness_ed25519"
ALLOWED="${ALLOWED_OVERRIDE:-.witness/allowed_signers}"
SIGNER="$(whoami)"

# ── subcommand: init ───────────────────────────────────────────────
do_init() {
  if [ ! -f "$KEY" ] || [ "$FORCE" -eq 1 ]; then
    [ "$FORCE" -eq 1 ] && rm -f "$KEY" "$KEY.pub"
    mkdir -p "$(dirname "$KEY")"
    ssh-keygen -t ed25519 -f "$KEY" -N "" -C "witness@$(whoami)" >/dev/null
    echo "generated $KEY"
  fi

  mkdir -p .witness
  PUB=$(cat "$KEY.pub")

  if [ ! -f "$ALLOWED" ]; then
    echo "$SIGNER namespaces=\"$NS\" $PUB" > "$ALLOWED"
    echo "created $ALLOWED with namespaces=\"$NS\" — commit this file"
    return
  fi

  # If our pubkey line already has this namespace, no-op.
  if grep -F "$PUB" "$ALLOWED" | grep -Eq "namespaces=\"[^\"]*\\b${NS}\\b[^\"]*\""; then
    return 0
  fi

  # If our pubkey is present but missing this namespace, extend the field.
  if grep -Fq "$PUB" "$ALLOWED"; then
    tmp=$(mktemp)
    awk -v pub="$PUB" -v ns="$NS" '
      {
        if (index($0, pub) > 0 && match($0, /namespaces="[^"]*"/)) {
          cur = substr($0, RSTART+12, RLENGTH-13)
          if (index(cur, ns) == 0) {
            new_ns = cur "," ns
            sub(/namespaces="[^"]*"/, "namespaces=\"" new_ns "\"", $0)
          }
        }
        print
      }
    ' "$ALLOWED" > "$tmp"
    mv "$tmp" "$ALLOWED"
    echo "extended namespaces to include $NS in $ALLOWED — commit this change"
  else
    echo "$SIGNER namespaces=\"$NS\" $PUB" >> "$ALLOWED"
    echo "appended pubkey with $NS namespace to $ALLOWED — commit this file"
  fi
}

# ── subcommand: sign ───────────────────────────────────────────────
do_sign() {
  [ -z "$SLUG" ] && { echo "usage: $0 sign --namespace=$NS <slug>" >&2; exit 1; }
  [[ "$SLUG" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "slug must be kebab/snake-case ASCII" >&2; exit 1; }

  do_init  # auto-init keypair + allowed_signers (idempotent, silent on no-op)

  mkdir -p .witness
  # File name: assert-presence uses prefix; decommission uses bare slug
  case "$NS" in
    assert-presence) F=".witness/assert-presence-${SLUG}.txt" ;;
    *)               F=".witness/${SLUG}.txt" ;;
  esac

  if [ ! -e "$F" ]; then
    {
      echo "# ${HEADERS[0]%:} ${SLUG}"
      case "$NS" in
        decommission)
          echo "# decommissioned: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
          echo "# reason: <one-line why this was removed>"
          echo "# rollback: <how to restore if needed>"
          echo ""
          echo "# Add assertions below. One per line. Lines starting with # are comments."
          echo "# Grammar:"
          echo "#   ABSENT_PATH: <path>            file/dir/symlink must not exist (~ expanded)"
          echo "#   ABSENT_CRON_MATCH: <pattern>   crontab -l must contain no line matching substring"
          echo "#   ABSENT_LAUNCHD: <label>        launchctl list must contain no matching label"
          echo "#   ABSENT_PROCESS_MATCH: <pattern>  pgrep -lf must find no match"
          ;;
        assert-presence)
          echo "# asserted: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
          echo "# agent: <agent name, or \"human\", or PR #>"
          echo "# evidence: <what proves this works — passing test, fixed file:line, working command>"
          echo ""
          echo "# Add assertions below. Grammar:"
          echo "#   PRESENT_FILE: <path>"
          echo "#   PRESENT_MARKER: <path> :: <substring>  (~ expanded; separator is \" :: \")"
          ;;
      esac
    } > "$F"
    echo "created $F — opening editor"
  else
    echo "$F exists — reopening for edit"
  fi

  # Editor loop — skipped in WITNESS_NONINTERACTIVE (test affordance)
  if [ "${WITNESS_NONINTERACTIVE:-0}" != "1" ]; then
    "${EDITOR:-vi}" "$F"
  fi

  for hdr in "${HEADERS[@]}"; do
    if ! grep -q "^# ${hdr}" "$F"; then
      echo "✗ missing required header: # ${hdr} ..." >&2
      exit 1
    fi
  done

  case "$GRAMMAR" in
    absent)  re='^(ABSENT_PATH|ABSENT_CRON_MATCH|ABSENT_LAUNCHD|ABSENT_PROCESS_MATCH):' ;;
    present) re='^(PRESENT_FILE|PRESENT_MARKER):' ;;
  esac
  if ! grep -Eq "$re" "$F"; then
    echo "✗ no ${GRAMMAR^^}_* assertions found in $F" >&2
    exit 1
  fi

  ssh-keygen -Y sign -f "$KEY" -n "$NS" "$F" >/dev/null
  echo "✓ signed $F.sig"
  echo ""
  echo "next steps:"
  echo "  1. git add $F $F.sig $ALLOWED"
  echo "  2. bash $(dirname "$0")/witness.sh verify --namespace=$NS   # confirm assertions hold now"
  echo "  3. git commit"
}

# ── subcommand: verify ─────────────────────────────────────────────
do_verify() {
  shopt -s nullglob
  WITNESSES=( $GLOB )
  if [ ${#WITNESSES[@]} -eq 0 ]; then
    echo "no witnesses matching $GLOB"
    return 0
  fi

  if [ ! -f "$ALLOWED" ]; then
    echo "✗ missing $ALLOWED — cannot verify signatures" >&2
    exit 1
  fi
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "✗ ssh-keygen not found" >&2
    exit 1
  fi

  local fail=0
  report() { echo "✗ $*"; fail=1; }

  for txt in "${WITNESSES[@]}"; do
    local sig="${txt}.sig"
    if [ ! -f "$sig" ]; then
      report "MISSING SIGNATURE: $sig"
      continue
    fi

    if ! ssh-keygen -Y verify -f "$ALLOWED" -I "$SIGNER" -n "$NS" -s "$sig" < "$txt" >/dev/null 2>&1; then
      report "SIGNATURE INVALID: $txt"
      continue
    fi

    for hdr in "${HEADERS[@]}"; do
      grep -q "^# ${hdr}" "$txt" || report "MISSING HEADER ($txt): # ${hdr}"
    done

    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// }" ]] && continue
      case "$line" in
        ABSENT_PATH:*)
          local path
          path=$(echo "${line#ABSENT_PATH:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          path="${path/#\~/$HOME}"
          if [ -e "$path" ] || [ -L "$path" ]; then
            report "ORPHAN PATH ($txt): $path still exists"
          fi
          ;;
        ABSENT_CRON_MATCH:*)
          local pat
          pat=$(echo "${line#ABSENT_CRON_MATCH:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          if crontab -l 2>/dev/null | grep -Fq -- "$pat"; then
            report "ORPHAN CRON ($txt): pattern '$pat' still in crontab"
          fi
          ;;
        ABSENT_LAUNCHD:*)
          local label
          label=$(echo "${line#ABSENT_LAUNCHD:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          if launchctl list 2>/dev/null | awk '{print $3}' | grep -Fxq -- "$label"; then
            report "ORPHAN LAUNCHD ($txt): $label still loaded"
          fi
          ;;
        ABSENT_PROCESS_MATCH:*)
          local pat
          pat=$(echo "${line#ABSENT_PROCESS_MATCH:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          if pgrep -lf -- "$pat" >/dev/null 2>&1; then
            report "ORPHAN PROCESS ($txt): $(pgrep -lf -- "$pat")"
          fi
          ;;
        PRESENT_FILE:*)
          local path
          path=$(echo "${line#PRESENT_FILE:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          path="${path/#\~/$HOME}"
          if [ ! -e "$path" ]; then
            report "ASSERTION REGRESSION ($txt): file '$path' is missing"
          fi
          ;;
        PRESENT_MARKER:*)
          local spec path marker
          spec=$(echo "${line#PRESENT_MARKER:}" | sed 's/^[[:space:]]*//')
          if [[ "$spec" != *" :: "* ]]; then
            report "MALFORMED ($txt): PRESENT_MARKER needs ' :: ' separator — got: $spec"
            continue
          fi
          path="${spec%% :: *}"
          marker="${spec#* :: }"
          path="${path/#\~/$HOME}"
          if [ ! -f "$path" ]; then
            report "ASSERTION REGRESSION ($txt): file '$path' is missing"
          elif ! grep -Fq -- "$marker" "$path"; then
            report "ASSERTION REGRESSION ($txt): marker '$marker' not found in $path"
          fi
          ;;
        *)
          report "UNKNOWN ASSERTION ($txt): $line"
          ;;
      esac
    done < "$txt"
  done

  echo ""
  if [ "$fail" -ne 0 ]; then
    echo "$BANNER — orphans detected. Investigate before continuing."
    exit 2
  fi
  echo "✓ ${#WITNESSES[@]} witness(es) verified"
}

# ── dispatch ────────────────────────────────────────────────────────
case "$cmd" in
  init)   do_init ;;
  sign)   do_sign ;;
  verify) do_verify ;;
  *)      echo "unknown subcommand: $cmd (expected: init | sign | verify)" >&2; exit 1 ;;
esac
