---
name: complexity-check
description: "Measure cyclomatic complexity per function via `lizard`. Use when reviewing hotspots before refactoring. Advisory only. Don't use for bash/shell (unsupported) or Big-O (mh:performance-optimizer)."
argument-hint: "[path] [--ccn N]"
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

If missing: tell the user, don't fabricate a result. Offer `pip install lizard` or
`pipx install lizard` and stop — do not silently report "0 hotspots" as if the scan ran.

## Usage

```bash
lizard "${TARGET_PATH:-.}" -w -s cyclomatic_complexity -i -1
```

- `-w` — clang-style warnings only: `file:line: warning: func has N NLOC, M CCN, ...`
  (functions under the threshold print nothing).
- `-s cyclomatic_complexity` — sort warnings by CCN, worst first.
- `-C N` — override the default threshold (15) if the caller names one.
- `-i -1` — **required**, not optional: without it `lizard` exits 1 on any
  threshold-breaching function (verified directly — an unqualified run is a blocking
  gate by default, every dedicated complexity CLI checked works the same way: xenon,
  gocyclo `-over`, gocognit `-over` all exit non-zero too). `-i -1` is lizard's own
  documented switch for "exit 0 regardless of warning count" — this is what actually
  keeps the scan advisory, not a property of the tool you can assume.
- `--exclude "pattern"` — extra excludes; `.gitignore` is already honored by default.
- Target a path (arg or `argument-hint`) to scope a single module instead of the whole repo.

Advisory by design choice, not by default — deny is reserved for irrecoverable actions in
this repo, and a complexity score, while a real signal, is a weak one: peer-reviewed
studies find cyclomatic-complexity-derived features are noisy defect predictors (~0.55-0.58
accuracy, 24-30% recall for the faulty class) and that cognitive complexity is not
meaningfully better correlated with understandability than cyclomatic complexity or even
plain LOC. Not strong enough evidence to block a commit on. Never drop `-i -1` or wire
this into a blocking hook without the user asking for that explicitly.

## Reading the output

Each warning line is one function over threshold: file, line, function name, CCN, NLOC
(lines of code), token count, parameter count. Report the worst 5-10 by CCN with
file:line, then a one-line read: what makes it branchy (nested conditionals, a big
switch, unrolled validation), not a restatement of the number.

A clean run (`No thresholds exceeded...`) means nothing to report — say so in one line,
don't pad it.

Done when: every function above threshold has a file:line and a one-line cause, or the
run confirms a clean scan.

## Known gap

`lizard` does not parse bash/shell (not in its supported-language list: cpp, java,
csharp, javascript, typescript, tsx, python, go, ruby, php, swift, rust, kotlin, and
others — no shell). This repo is bash-heavy, so shell scripts get silently skipped, not
scored zero — say that explicitly rather than implying full coverage.

<!-- ponytail: bash coverage gap, add a shell-specific CCN heuristic (or a dedicated
     tool) only if a real need shows up — don't build one speculatively. -->

## Suggested next step

Hotspots found → `ponytail:ponytail-review` or `mattpocock-skills:code-review` for a
broader look at whether the complexity is warranted. Clean scan → no action needed.
