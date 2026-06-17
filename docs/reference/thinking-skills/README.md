# thinking-skills — vendored reference copy

A verbatim copy of the **skills** from
[cc-thinking-skills](https://github.com/tjboudreaux/cc-thinking-skills) by TJ Boudreaux,
stored here as a **common-references library** — not as invokable kbg skills.

| | |
|---|---|
| Source | https://github.com/tjboudreaux/cc-thinking-skills |
| Vendored commit | `0313ee0d476bf9db2c38ad8bd11d9933a61350d4` |
| License | MIT © 2025 TJ Boudreaux — see [`LICENSE`](LICENSE) (retained per MIT) |
| Contents | `skills/` (39 mental-model `SKILL.md` files) + [`UPSTREAM-README.md`](UPSTREAM-README.md) |

## Why this is under `docs/`, not `skills/`

The plugin auto-discovers invokable skills **only** from the repo-root `skills/` directory.
Keeping these copies under `docs/reference/` means they are **reference material you read**,
never skills Claude can trigger. **Do not move this tree into the root `skills/` dir** — that
would register 39 unvetted skills and break the fleet count (`harness-audit` globs
`skills/*/SKILL.md`).

## Read this before treating any of these as advice

cc-thinking-skills runs its own replication-gated eval and reports — in
[`UPSTREAM-README.md`](UPSTREAM-README.md) — that **none of the 39 skills clears its own
accuracy bar**; one (`margin-of-safety`) measurably *hurt* accuracy (−10pp). Treat these as
**structured-reasoning scaffolds and shared vocabulary, not a proven accuracy boost.**

## Index + how kbg already applies these

The catalog mapping each model to where kbg already does it lives one level up:
[`../reasoning-models.md`](../reasoning-models.md).
