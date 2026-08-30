#!/usr/bin/env bash
# 34. matt-pocock doctrine conformance — emit INFO findings when a skill's
# description + body fails one or more of the checks below. Doctrine source:
# matt's `writing-for-agents` skill (renamed from `writing-great-skills` in
# matt v1.2.0) via CLAUDE.md's "Skill authoring doctrine (matt-pocock)" section and
# the docs/skill-template/SKILL.md "## Design checks" block. Checks 1, 4, 5
# proxy matt elements (leading words, completion criterion, no-op test);
# check 2 (≤25 words) is the KBG-NATIVE token-budget cap, not matt's; check 3
# (trigger-per-branch) started as a script-only addition and v1.2 promoted
# the same idea upstream ("one trigger per branch" in the context-pointer
# rules):
#
#   1. Leading word — coined term in the first 10 words of description.
#      Matt vocabulary: grill, seam, vertical slice, premature completion,
#      no-op, sediment, sprawl, legwork, co-location, context-pointer, cache.
#   2. Description ≤ 25 words (CLAUDE.md cap; check #20 measures chars).
#   3. One trigger per branch — ≥ 2 "Use when / Trigger when / Trigger on /
#      Invoke when / ALWAYS" clauses smells like synonym-rewriting.
#   4. Completion criterion — body has a "Verify / Confirm / Check that /
#      Expect / Validate" token in at least one procedure step. Hardest
#      to detect mechanically; we report absence as an INFO hint, never CRIT.
#   5. No-op test — body has a substantive procedure step (≥ 3 lines under
#      "## " headings); a skill that is all-intro and no procedure is
#      candidate for the no-op test rewrite.
#
# The old "failure-mode guard" and "two-cuts" labels have no shell check —
# and matt's v1.2 rewrite dissolved both as named terms (distributed into
# writing-for-agents' When-to-split/Pruning prose), so a proxy is now doubly
# unwarranted. A numbered-window regex proxy for failure-mode guard was tried
# and retired (2026-07-16): it was vacuous before the reset-bug fix (any
# trigger word anywhere later in the file passed) and 5/5 false-positive
# after (every flagged skill already named its failure mode in a prose
# section or bullet list outside any numbered-step window — see CLAUDE.md's
# matt-doctrine-conformance history).
#
# Per memory `harness-audit-gauntlet-policy`, this is INFO-only. The check is
# the visibility layer for the doctrine rule in CLAUDE.md; tightening to
# WARN/CRIT deliberately rejects the WARN→CRIT escalation trap.
# Excluded: harness-audit (self-references the check); ideate (defensive:
# historically a skill+command twin with a shared description — the loop only
# sees skills/*/SKILL.md, so the entry is inert while only the command form
# exists). kbg-help's entry (same twin rationale) was removed 2026-08-24 (#80)
# with its command — no skills/kbg-help/ exists, so the entry was dead anyway.
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/skills"/*/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  name=$(basename "$(dirname "$f")")
  case "$name" in
    harness-audit|ideate) continue ;;
  esac

  desc=$(fm_get "$f" "description" --block)

  # Coined-term leading word (check 1). Letter-only before the first comma
  # or period inside the description. We test the FIRST word token only —
  # if it's in the matt vocabulary, check passes silently. Otherwise we
  # emit an INFO; downstream the user judges whether the leading word is
  # itself a coined concept we recognise (matt's vocabulary is illustrative,
  # not exhaustive, so we keep the list focused on the highest-signal terms
  # already used elsewhere in kbg).
  # First word is lowercased and stripped of trailing punctuation so coined
  # compounds with hyphens/colons still match the vocabulary (e.g.
  # "Grill-me:" → "grill-me", "Cage:" → "cage"). Tokens with embedded
  # separators are kept whole; the vocabulary entries mirror that shape
  # (grill-me, not grill_me) so coined compounds recruit their prior intact.
  first_word=$(printf '%s' "$desc" | awk '{print tolower($1); exit}' | tr -d ':,;')
  case "$first_word" in
    # matt canonical vocabulary — anchored in `writing-for-agents/SKILL.md`
    # (renamed from writing-great-skills in matt v1.2.0). sediment, sprawl,
    # legwork, and context-pointer predate v1.2 (confirmed against matt's
    # day-one GLOSSARY.md, commit bc4cf90); co-location and cache are the
    # real v1.2 additions (co-location confirmed via `git log -S`; cache
    # named in matt's own CHANGELOG.md for 1.2.0) — except frontier, whose
    # anchor is `grilling/SKILL.md`'s rounds mechanic. `two-cut`,
    # `recursion-ceiling`, `cage`, `deep-fake`, `unfake`, and `ratchet` were
    # removed 2026-08-30: none ever appeared in matt's git history (checked
    # via `git log --all -i -S"<term>"` across every branch plus the
    # original GLOSSARY.md) — fabricated vocabulary, not a stale rename.
    grill|grill-me|seam|vertical-slice|vertical_slice|premature-completion|premature_completion|no-op|no_op|sediment|sprawl|legwork|frontier|co-location|context-pointer|cache) : ;;  # silent
    # kbg-native coined compounds — high-signal terms already used across
    # kbg skill descriptions. Adding to the vocabulary is a one-line edit
    # here; extending further belongs in a dedicated audit-policy pass.
    # M2-M11 additions: leading-word recuts from description-trim pass 2026-06-30
    # (audit script check #34 silently accepts the prior).
    # M12 additions (2026-06-30, 0-INFO goal pass): framework proper-nouns (a
    # pattern-catalog skill's first word IS the framework — a named concept that
    # recruits a prior, not a generic noun; forcing a matt coined term onto a
    # framework catalog degrades the desc) + recognized kbg coined concepts.
    # Generic imperative verbs (run/use/manage/create/analyze/prioritize/orchestrate/audits)
    # are deliberately NOT added — those descs are recast to a vocab lead instead.
    # humanize: skill-name-derived lead for tech-humanize, same treatment as
    # teach/score/incident/triage — not a generic verb, the skill's own name.
    # M13 additions (2026-08-18, INFO-review pass): wcag/fowler are the same
    # framework-proper-noun class as M12's adonisjs/drizzle/fastapi — an
    # unambiguous named standard/taxonomy, not a generic noun, even read
    # standalone. tier and finish are kbg-native coined pipeline-stage verbs
    # (the since-retired review-pr pipeline's SCRUTINIZE-4 tiering /
    # decide-and-write-state finish step — skills removed 2026-08-24 #82,
    # entries kept as historical allowlist), same class as the
    # already-accepted score/triage. pre-flight is
    # a real, specific engineering idiom (a gate-before-launch check), not a
    # generic noun — same bar as no-op/two-cut. next.js and
    # frontend-design-direction follow M12's framework-proper-noun and the
    # humanize skill-name-derived-lead precedents respectively.
    # M14 additions (2026-08-28, "fix all WARN/INFO" pass): cost-report,
    # frame, ideate-search, complexity-check, compliance-audit, deep-audit,
    # review-fixtures, risk-check, test-coverage, post-mortem, refactor-clean,
    # tiered are skill-name-derived leads, same class as incident/triage/
    # humanize. sweep is bug-sweep's own name, same class as scan. ship
    # covers both ship-merge/ship-release (a coined pipeline-stage verb, same
    # class as tier/finish). summarize is tech-humanize's own precedent
    # applied literally: the skill's own name used as its own leading verb.
    # ingest is wiki-ingest's own name fragment, same class as sweep/scan.
    synthesise-seam|slice|doctrine|doctrine-backed|triage|mental-model|catalogue|catalog|test-driven|deep-module|diagnosis|build|compact|scan|teach|adonisjs|backend|frontend|drizzle|effect-ts|fastapi|grpc|hono|langchain|tauri|mysql/mariadb|pythonic|score|incident|router|eval-driven|dart/flutter|humanize|prep-map|pr|typescript|db/sql|fix-authenticity|requirement-coverage|wcag|fowler|tier|pre-flight|finish|next.js|frontend-design-direction|cost-report|frame|ideate-search|sweep|complexity-check|compliance-audit|deep-audit|review-fixtures|risk-check|test-coverage|post-mortem|refactor-clean|ship|summarize|tiered|ingest) : ;;  # silent
    *) info "$name: description does not open with a matt-style coined term (first word: '$first_word') — leading word recruits a pretrained prior, not a generic noun" ;;
  esac

  # Word-count cap (check 2). CLAUDE.md says ≤25 words. We compute on the
  # description's body text (block scalar stripped of indent by fm_get).
  desc_wc=$(printf '%s' "$desc" | wc -w | tr -d ' ')
  if [ "$desc_wc" -gt 25 ]; then
    info "$name: description is $desc_wc words (>25 cap from CLAUDE.md — trims context load; check #20 measures chars not words, this is the word-count twin)"
  fi

  # Trigger repetition (check 3). Multiple "Use when…" / "Trigger when…" /
  # "Trigger on…" clauses indicate the same branch rewritten as synonyms
  # — a synonym-rewrite smell. Aim is to flag over-specification, not to
  # mandate ≤1 (a skill that genuinely has two routes can have two
  # triggers, but four is a rewrite). We treat ≥3 as INFO-worthy.
  # `|| true` neutralises `set -e` propagation when the pipe returns 1
  # (no trigger matches at all) — under pipefail the substitution would
  # otherwise exit 1 and kill the for-loop iteration.
  triggers=$(printf '%s' "$desc" | grep -oiE 'use when|trigger when|trigger on|invoke when|use proactively when|always trigger|use after' | sort -u | wc -l | tr -d ' ') || true
  if [ "$triggers" -ge 3 ]; then
    info "$name: description has $triggers distinct trigger clauses — matt's one-trigger-per-branch treats synonym rewrites as duplication; consolidate or branch"
  fi

  # Body-side checks (4, 5, 6). Read the whole file once; tests are line-scoped.
  body=$(cat "$f")

  # Completion criterion (check 4). An absent verify/confirm/check token in
  # the body means there is no sentence telling the agent "the work is
  # done when X". We can't LLM-judge the criterion's quality; we flag the
  # absence as INFO so the author can read the skill and decide.
  # Inverted to `if cmd; then : ; else info; fi` so both branches end with
  # status 0; `if ! cmd; then info; fi` returns 1 when cmd succeeds (the
  # taken branch is the empty `else`), tripping set -e in the for-loop.
  if printf '%s' "$body" | grep -qiE '\b(verify|confirm|check that|expect|validate|done when)\b'; then
    :
  else
    info "$name: body has no 'verify / confirm / done when' token — matt's completion-criterion rule requires every procedure to end on a checkable signal"
  fi

  # No-op test (check 5). A skill with fewer than 5 substantive body lines
  # (post-frontmatter, blank-line-stripped) is a candidate for the no-op
  # rewrite — every sentence must change behaviour vs the default.
  body_lines=$(printf '%s' "$body" | awk '
    /^---/ { in_fm = !in_fm; next }
    in_fm   { next }
    /^[[:space:]]*$/ { next }
    { c++ }
    END { print c + 0 }
  ')
  if [ "$body_lines" -lt 5 ]; then
    info "$name: body has only $body_lines substantive lines — matt's no-op test says every sentence must change behaviour; very-thin skills often have stale scaffolding"
  fi
done
