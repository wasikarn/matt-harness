#!/usr/bin/env bash
# frontmatter-helpers.sh — shared frontmatter helpers for harness-audit + inventory scripts.
#
# Sourced (not executed) by the 3 callers; this file defines functions and
# exports one constant. All parsers read the YAML frontmatter block between
# the first two `---` markers; behavior is preserved from the 5 separate
# in-line parsers this consolidates.
#
# Functions:
#   fm_get <file> <key> [--block]
#       Print the value of <key> from the first ---...--- block in <file>.
#       Default: single-line value (first line after `key:`, with optional
#       surrounding quotes stripped). Suitable for `description: foo` and
#       `tools: A, B, C` style keys where the body is a one-liner.
#       --block: handle `|`, `|-`, `|`, `>`, `>-`, `>+` block scalars —
#       print the multi-line body with leading indent stripped from each
#       line. Matches the original audit.sh `extract_fm` semantics.
#       Returns empty string if file missing, no frontmatter, or key absent.
#
#   fm_has <file> <key>
#       Exit 0 if <key> appears as a top-level key in the first frontmatter
#       block, 1 otherwise. Empty value still counts as present.
#
#   fm_in_fm_section <file>
#       Exit 0 if <file> has any frontmatter (first two `---` markers both
#       present), 1 otherwise.
#
#   fm_hook_desc <file>
#       Print the first non-shebang, non-license-prefixed `# ...` comment
#       line from a hook script. NOT a YAML frontmatter parser — hook files
#       are .sh/.py, not markdown, so the "description" is a code comment.
#       Kept separate from fm_get so the frontmatter contract stays clean.
#
# Constants:
#   SKIP_SCAFFOLD_GLOB
#       The `[!_]*/` glob that excludes _-prefixed scaffolds (_template,
#       _archive) from per-skill directory walks. The convention lives in
#       install.sh and is repeated in audit.sh / inventory.sh /
#       inventory-boundary.sh. Exporting the constant lets each call site
#       write the same glob without re-deriving it.

# SKIP_SCAFFOLD_GLOB — exclude _-prefixed scaffolds from skill directory walks.
# See install.sh for the canonical definition; this export lets every
# caller share the same glob without re-deriving it inline.
#
# Note: bash treats variable expansion as a literal string, not a glob
# pattern. The constant is exported for documentation / grep-anchoring
# purposes — the inline literal `[!_]*/` is still required in the few
# `for d in "$path"/[!_]*/` call sites. A future caller that wants to
# avoid the inline literal can switch to a case-statement filter.
SKIP_SCAFFOLD_GLOB='[!_]*/'
export SKIP_SCAFFOLD_GLOB

# _FM_CACHE — per-(file,key,flags) frontmatter memoization for audit/inventory.
# Populated once in the caller's MAIN shell (audit.sh builds it before its checks
# loop; see the build pass there). fm_get reads it first and falls back to awk
# on a miss, so correctness never depends on the cache -- it is a pure speedup.
# Checks call fm_get inside $(...) subshells, which inherit this array by
# fork-copy, so a cache built in the main shell is visible (read-only) to every
# subshell call without each subshell re-spawning awk (~460 redundant awk
# spawns/audit run -> one build pass). Declared global (-g) so it survives
# across the sourced-check-files boundary. Requires bash 4+ (associative
# arrays); on older bash the declare no-ops and fm_get simply always falls
# through to awk (correct, just unspeeded).
declare -gA _FM_CACHE 2>/dev/null || true

# fm_get — read a single frontmatter value.
# Block-scalar handling: block scalars (|, |-, |+, >, >-, >+) start the body
# on the NEXT line at indent > 0. We print the body line-by-line with the
# indent stripped. A non-indented line ends the block (block_indent tracking
# would be more robust against mixed indents but the existing data uses
# uniform 2-space indent, and the original extract_fm was a one-liner — we
# preserve that contract and rely on uniform indent in the source files).
fm_get() {
  local file="$1" key="$2" want_block="${3:-}"
  [ -f "$file" ] || { return 0; }
  local _ck="${file}|${key}|${want_block}"
  # Cache hit: reproduce awk's exact stdout (non-empty value -> "value\n",
  # absent key -> nothing) and return without spawning awk. The ${+set} form is
  # safe under set -u and distinguishes a cached empty (set) from never-asked
  # (unset), so absent keys are cached too and never re-spawn awk.
  if [ -n "${_FM_CACHE[$_ck]+set}" ]; then
    local _v="${_FM_CACHE[$_ck]}"
    [ -n "$_v" ] && printf '%s\n' "$_v"
    return 0
  fi
  local _out
  if [ "$want_block" = "--block" ]; then
    _out=$(awk -v k="$key" '
      BEGIN { in_fm = 0; block = 0 }
      /^---[[:space:]]*$/ { in_fm = !in_fm; if (!in_fm) exit; next }
      in_fm && $0 ~ "^"k":" {
        line = $0
        sub(/^[^:]*:[[:space:]]*/, "", line)
        if (line ~ /^[|>][[:space:]]*[+-]?$/) { block = 1; next }
        gsub(/^"|"$/, "", line)
        print line
        exit
      }
      in_fm && block {
        if ($0 ~ /^[[:space:]]*$/) { next }
        if ($0 !~ /^[[:space:]]/) { exit }
        sub(/^[[:space:]]*/, "", $0)
        print
      }
    ' "$file")
  else
    _out=$(awk -v k="$key" '
      BEGIN { in_fm = 0 }
      /^---[[:space:]]*$/ { in_fm = !in_fm; if (!in_fm) exit; next }
      in_fm && $0 ~ "^"k":" {
        sub(/^[^:]*:[[:space:]]*/, "")
        gsub(/^"|"$/, "")
        print
        exit
      }
    ' "$file")
  fi
  # Write-through (persists in the main shell; a write inside a $(...) subshell
  # is lost, which is harmless -- the pre-built cache is what the subshells read).
  _FM_CACHE[$_ck]="$_out"
  [ -n "$_out" ] && printf '%s\n' "$_out"
  return 0
}

# fm_has — does a key exist in the first frontmatter block?
# A key with an empty value still counts as present (line matches `key:`).
fm_has() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  awk -v k="$key" '
    BEGIN { in_fm = 0; found = 0 }
    /^---[[:space:]]*$/ { in_fm = !in_fm; if (!in_fm) exit; next }
    in_fm && $0 ~ "^"k":" { found = 1; exit }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

# fm_in_fm_section — does the file have any frontmatter at all?
# Returns 0 if two `---` markers are seen, 1 otherwise. Reads from the
# top of the file (no early-exit on no-frontmatter to keep the awk minimal).
fm_in_fm_section() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk '
    /^---[[:space:]]*$/ { count++ }
    count >= 2 { exit 0 }
    END { exit (count >= 2 ? 0 : 1) }
  ' "$file"
}

# fm_hook_desc — extract the first descriptive comment PARAGRAPH from a hook
# file (concatenated to one line). NOT a frontmatter parser: hook files are
# .sh/.py with a shebang line and a series of `#` comments, not a YAML block.
#
# Revised 2026-07-15: the original single-line version (`print; exit` on the
# first `# ` match) truncated any hook whose lead comment spans multiple
# lines -- e.g. flow-nudge.sh's description cut off mid-sentence at a
# trailing comma -- and had no guard against a `disable=...` pragma comment,
# which got printed as if it were the description (see test-flow-nudge.sh).
# Fix: skip shebang/Author/Copyright/License/SPDX/pragma-directive lines,
# then accumulate consecutive `# ` lines into one space-joined paragraph,
# stopping at the first blank comment line (`#`
# alone), the first non-comment line, or a 12-line cap (worktree-guard.py has
# no blank-comment break and runs 16 lines straight into `import` -- the cap
# keeps that one outlier from ballooning a table cell; every other current
# hook file's lead paragraph is <=9 lines and finishes naturally well under
# the cap, so it never fires a spurious truncation marker on them).
fm_hook_desc() {
  awk '
    /^#!/                                          { next }
    /^# *(Author|Copyright|License|SPDX|shellcheck)/ { next }
    /^# *$/                                        { if (buf != "") exit; next }
    /^# /                                           { sub(/^# */, ""); buf = (buf == "" ? $0 : buf " " $0); n++; if (n >= 12) { print buf " […]"; exit } next }
    { if (buf != "") exit }
    END { if (buf != "") print buf }
  ' "$1"
}
