#!/usr/bin/env bash
# 52. Output-style body size outlier — flag output-styles/*.md files large
# enough to warrant a token-optimizer pass. INFO only, mirrors checks
# 38/51's threshold and severity for the identical reason (some register
# files are legitimately dense) — same 20K-char threshold, not re-derived
# from the output-styles/ distribution. (This comment previously cited
# "42/51/60" — 42 was never a body-size check and 60 never existed; a
# stale reference caught during #112's renumbering sweep, unrelated to
# that ticket's own commands/-retirement scope. The commands-side sibling
# that used to complete this family, command-body-size-outlier, was
# deleted with #112 — commands/ retired as a surface type entirely.)
# Gap this closes: neither 38 nor 51 globs output-styles/*.md, so this
# surface has never been mechanically flagged for size — confirmed
# 2026-08-18 (mattpocock wait-what/writing-for-agents doctrine session):
# output-styles/staff-eng.md carries `force-for-plugin: true`, meaning it is
# injected UNCONDITIONALLY every session the plugin is enabled, unlike a
# skill/command/agent body (conditionally loaded on invocation) — the same
# always-on cost profile as CLAUDE.md/METHODOLOGY.md, just with no check at
# all watching it. Kept INFO (not WARN) to match the established 38/51
# severity convention rather than inventing a new tier on top of it; the
# always-on-cost distinction is real but doesn't by itself justify deviating
# from the sibling checks' severity, only from their blind spot.
SIZE_THRESHOLD_CHARS=20000
for _f in "$CLAUDE_DIR"/output-styles/*.md; do
  [ -f "$_f" ] || continue
  _chars=$(wc -c < "$_f" | tr -d ' ')
  if [ "$_chars" -gt "$SIZE_THRESHOLD_CHARS" ]; then
    _tokens=$((_chars / 4))
    _rel="${_f#"$CLAUDE_DIR"/}"
    info "'$_rel' is ${_chars} chars (~${_tokens} tokens, fleet threshold ${SIZE_THRESHOLD_CHARS}) — unconditionally loaded every session (force-for-plugin), so this cost is paid every turn, not just on invocation; consider a token-optimizer pass"
  fi
done
unset _f _chars _tokens _rel SIZE_THRESHOLD_CHARS
