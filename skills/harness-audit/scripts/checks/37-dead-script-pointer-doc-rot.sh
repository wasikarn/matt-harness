#!/usr/bin/env bash
# 37. Dead script-pointer doc-rot (skill/command/agent bodies invoke a script that does not exist)
# Matt "beware doc-rot": a surface body that tells the model to run
# `bash .../scripts/NAME.sh` (or a `python3 .../NAME.py` invocation) for a file
# that exists nowhere in the fleet is an instruct-the-model-to-run-a-missing-
# script defect — it crashes on invoke. The matt-first cut (242->87) deleted
# surfaces but left such pointers dangling; this guard is the regression fence.
#
# Scope: only EXECUTABLE invocations — a line that runs the script via `bash`,
# `sh`, `python3`, `python`, `node`, or `exec`. Descriptive prose that NAMES a
# script to say it is absent/retired (e.g. "its backing scripts/x.sh is absent")
# is deliberately not matched: the match requires an interpreter token before
# the path. WARN, not CRIT — advisory, matching the operating model (sensors
# journal; the CRIT set is reserved for the irrecoverable/tamper class).
for _f in "$CLAUDE_DIR"/skills/*/SKILL.md "$CLAUDE_DIR"/skills/*/reference.md \
          "$CLAUDE_DIR"/commands/*.md "$CLAUDE_DIR"/commands/*/COMMAND.md \
          "$CLAUDE_DIR"/agents/*.md; do
  [ -f "$_f" ] || continue
  # Pull interpreter-prefixed script paths: <interp> [flags] .../scripts/NAME.(sh|py|js)
  # Tolerate a ${VAR}/ or path prefix before scripts/; capture the basename.
  while IFS= read -r _ref; do
    [ -z "$_ref" ] && continue
    _base=$(basename "$_ref")
    # Resolve against the whole fleet (a wrapper may live in any skill's scripts/).
    # Exclude .git and .scratch (transient/untracked). Existence anywhere = live.
    if ! find "$CLAUDE_DIR" -name "$_base" -not -path '*/.git/*' -not -path '*/.scratch/*' 2>/dev/null | grep -q .; then
      warn "dead script-pointer in ${_f#"$CLAUDE_DIR"/}: invokes '$_ref' but no '$_base' exists in the fleet (doc-rot — crashes on invoke)"
    fi
  done < <(grep -hoE '(bash|sh|python3|python|node|exec)[[:space:]]+[^|;&]*scripts/[A-Za-z0-9_./${}-]+\.(sh|py|js)' "$_f" 2>/dev/null \
             | grep -oE 'scripts/[A-Za-z0-9_./${}-]+\.(sh|py|js)' \
             | sort -u)
done
unset _f _ref _base
