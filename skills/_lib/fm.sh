#!/usr/bin/env bash
# fm.sh — shared frontmatter helpers for harness-audit + inventory scripts.
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
  if [ "$want_block" = "--block" ]; then
    awk -v k="$key" '
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
    ' "$file"
  else
    awk -v k="$key" '
      BEGIN { in_fm = 0 }
      /^---[[:space:]]*$/ { in_fm = !in_fm; if (!in_fm) exit; next }
      in_fm && $0 ~ "^"k":" {
        sub(/^[^:]*:[[:space:]]*/, "")
        gsub(/^"|"$/, "")
        print
        exit
      }
    ' "$file"
  fi
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

# fm_hook_desc — extract the first descriptive `# ...` comment from a hook
# file. NOT a frontmatter parser: hook files are .sh/.py with a shebang
# line and a series of `#` comments, not a YAML block. Original semantics
# preserved verbatim from inventory.sh:29-35.
fm_hook_desc() {
  awk '
    /^#!/                                    { next }
    /^# *(Author|Copyright|License|SPDX)/    { next }
    /^# /                                    { sub(/^# */, ""); print; exit }
  ' "$1"
}
