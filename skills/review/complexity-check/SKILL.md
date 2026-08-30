---
name: complexity-check
description: "Complexity-check: cyclomatic complexity per function via `lizard`. Use when reviewing hotspots before refactoring. Advisory only. Don't use for bash/shell or Big-O (mh:performance-optimizer)."
argument-hint: "[path] [-C N]"
model: inherit
effort: medium
---

# Complexity Check

Report per-function cyclomatic complexity (CCN — count of independent branches: `if`,
`for`, `while`, `case`, `&&`/`||`, etc.) using [`lizard`](https://github.com/terryyin/lizard),
a single pure-Python CLI covering 27 languages. Reuses one already-installable dependency
instead of a per-language tool (radon/eslint-complexity/gocyclo) — the lazy rung that
actually holds here.

## Prerequisite (feature-detect, never silent fail-open)

```bash
command -v lizard >/dev/null 2>&1 || echo "not installed"
```

If missing: tell the user, don't fabricate a result — never silently report "0 hotspots"
as if the scan ran. Offer, in this order:

1. `uvx lizard <args>` — runs it without installing anything, if `uv` is on the box
   (`command -v uvx`). Substitute `uvx lizard` for `lizard` in every command below.
2. `pipx install lizard` or `pip install lizard` — a persistent install, when the user
   wants one.

Prefer (1) and stop there unless the user asks to install: a review skill should not
mutate the machine it is reviewing. Verified 2026-08-26 — this repo's own box has no
`lizard` on `PATH` and no `lizard` module, so the earlier verification runs here went
through the ephemeral path, and a `pip install`-only prerequisite would have read as
"unavailable" on the very machine the skill was written on.

## Usage

Two calls, both required. The second one alone cannot tell "clean" from "nothing was
parsed" — see the coverage check below.

```bash
# 1. coverage + counts (run this FIRST — it is the honesty check)
lizard "${TARGET_PATH:-.}" -i -1 2>&1 | tail -3

# 2. the hotspot lines themselves
lizard "${TARGET_PATH:-.}" -w -s cyclomatic_complexity -i -1
```

- `-w` — clang-style warnings only: `file:line: warning: func has N NLOC, M CCN, ...`
  (functions under the threshold print nothing at all).
- `-s cyclomatic_complexity` — sort warnings by CCN, worst first (verified: reorders
  output, it does not just echo source order).
- `-C N` — override the default threshold (15) if the caller names one. Long form is
  `--CCN` (capitalised); `--ccn` is not a real flag and argparse rejects it.
- `-i -1` — **required**, not optional: without it `lizard` exits 1 on any
  threshold-breaching function (verified directly — an unqualified run is a blocking
  gate by default, every dedicated complexity CLI checked works the same way: xenon,
  gocyclo `-over`, gocognit `-over` all exit non-zero too). `-i -1` is lizard's own
  documented switch for "exit 0 regardless of warning count" — this is what actually
  keeps the scan advisory, not a property of the tool you can assume.
- `--exclude "pattern"` — extra excludes; `.gitignore` is already honored by default.
- Target a path (arg or `argument-hint`) to scope a single module instead of the whole repo.

Advisory by design choice, not by default — deny is reserved for irrecoverable actions in
this repo, and a complexity score, while a real signal, is a weak one. Two peer-reviewed
studies (JSS 2023; ESEM 2020) agree that cognitive complexity is **not** better correlated
with code understandability than cyclomatic complexity or even plain LOC. A separate 2025
defect-prediction result — arXiv:2504.00477, a **preprint with no journal reference,
one classifier, one split**, so treat it as illustrative, not established — put the best
cyclomatic-derived feature set at ~0.55-0.58 accuracy with 24-30% recall on the faulty
class. Neither line of evidence is strong enough to block a commit on. Never drop `-i -1`
or wire this into a blocking hook without the user asking for that explicitly.

## Reading the output

Each warning line is one function over threshold. **Field order is NLOC first, CCN
second** — read positionally and you will report the line count as the complexity score:

```
path/file.py:170: warning: bash_write_targets has 124 NLOC, 82 CCN, 943 token, 1 PARAM, 162 length, 0 ND
                                                  └─ 1  └─ 2    └─ 3     └─ 4     └─ 5      └─ 6
```

1 NLOC (code lines) · 2 **CCN (the complexity score — this is the one you rank on)** ·
3 token count · 4 parameter count · 5 length (incl. blanks/comments) · 6 ND (nesting
depth; 0 for languages lizard can't parse structurally).

Report the worst 5-10 by CCN with file:line, then a one-line read: what makes it branchy
(nested conditionals, a big switch, unrolled validation), not a restatement of the number.

### Never report "clean" from empty output

Under `-w` a clean scan and a scan that parsed **nothing** both print zero bytes — they are
byte-identical. Only call 1's summary row separates them:

| `Total nloc` | `Warning cnt` | What to report |
|---|---|---|
| 0 | 0 | **Nothing was analyzed** — the target is all unsupported languages. Say that; never "clean". |
| > 0 | 0 | Genuinely clean: "N functions analyzed, none over threshold." |
| > 0 | > 0 | N over threshold — list them from call 2. |

Always state the analyzed count alongside the verdict, so zero-coverage can never render
as a pass. On this repo the bash-only case is real, not hypothetical: 55 shell scripts /
2,459 lines report `Total nloc 0` and emit no warning lines.

Done when: the analyzed count is stated, and either every function above threshold has a
file:line and a one-line cause, or the summary row confirms analyzed > 0 with 0 warnings.

## Known gap

`lizard` does not parse bash/shell (not in its 27-language list: cpp, java, csharp,
javascript, typescript, tsx, python, go, ruby, php, swift, rust, kotlin, and others —
no shell). Shell scripts are **skipped silently, not scored zero**, which is exactly the
false-clean trap above. This repo is bash-heavy, so a whole-repo run here reports on the
Python/JS surface only — say so rather than implying full coverage.

<!-- ponytail: bash coverage gap, add a shell-specific CCN heuristic (or a dedicated
     tool) only if a real need shows up — don't build one speculatively. -->

**Suggested next step:**
- Hotspots found → `ponytail:ponytail-review` or `mattpocock-skills:code-review` for a
  broader look at whether the complexity is warranted.
- Clean scan → no action needed.
