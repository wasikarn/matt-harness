# Workflow diagrams

Mermaid maps of how this harness actually runs. The first diagram is the index: every box
names a section below it.

**These diagrams describe shape, not census.** No count of skills, agents, or hooks is
written here on purpose — there is no drift check on this file, and a hand-typed number goes
stale silently. For the current inventory, read `BOUNDARY.md` (regenerated, drift-checked by
harness-audit check 16). For the wiring, read `hooks/hooks.json` and
`hooks/pretooluse-table.json` — both are the source these diagrams were drawn from.

---

## 1. Overall

```mermaid
flowchart TB
    A["Session start<br/>every surface loads from the plugin cache"]
    A --> B["2. Session lifecycle and hook dispatch"]
    B --> C["3. Request to executor routing"]
    C --> D["4. PreToolUse gate fan-out"]
    D --> E["Tool runs (Bash / Edit / Skill / Agent / MCP)"]
    E --> F["7. Orchestrate dispatch loop"]
    E --> G["8. Memory loop"]
    E --> H["5. Ship path"]
    H --> I["6. Adding or removing a surface"]
    I -.->|"version bump reaches the next session"| A

    classDef sec fill:#1f2937,stroke:#60a5fa,color:#e5e7eb
    class B,C,D,F,G,H,I sec
```

**This diagram is mirrored in `README.md`'s How it runs section — edit both or neither.**
Nothing checks the pair; it is two files kept in sync by hand.

The loop closes at the version bump: a change to a shipped surface reaches the *next*
session, never the running one. Same-version edits are silent no-ops — that is the single most common
way work here appears done and is not.

---

## 2. Session lifecycle and hook dispatch

Nine Claude Code events are wired. Every one except `PreToolUse` goes through
`hooks/dispatch-single.sh`, which is a filter that can drop the hook before its real script
ever runs.

```mermaid
flowchart LR
    subgraph EVENTS["Claude Code events"]
        direction TB
        E1["SessionStart"]
        E2["InstructionsLoaded"]
        E3["UserPromptSubmit"]
        E4["PreToolUse"]
        E5["PostToolUse"]
        E6["PostToolUseFailure"]
        E7["Stop"]
        E8["PreCompact"]
        E9["SessionEnd"]
    end

    E1 & E2 & E3 & E5 & E6 & E7 & E8 & E9 --> DS["dispatch-single.sh<br/>(id, tier, script)"]
    E4 --> DP["dispatch-pretooluse.sh<br/>(see section 4)"]

    DS --> K{"id in MH_DISABLED_HOOKS?"}
    K -->|"yes"| X["exit 0 — hook never runs"]
    K -->|"no"| T{"tier at or below MH_HOOK_PROFILE?"}
    T -->|"no"| X
    T -->|"yes"| R["exec the real script"]

    classDef drop fill:#3f1d1d,stroke:#f87171,color:#fecaca
    class X drop
```

**Tiers are ordinal:** `minimal(0) < standard(1) < strict(2)`. A hook fires when its own tier
is at or below the active profile. `MH_HOOK_PROFILE` defaults to `strict`, so an unset
environment runs everything — the filter is opt-in noise reduction, not a default-on
restriction.

What each tier means in practice:

| Tier | Behaviour | Typical carrier |
|---|---|---|
| `minimal` | Always on. Turning it off is a functionality loss, not noise reduction. | doctrine injection, env-var anchor, cost tracking |
| `standard` | On by default, first thing dropped when quieting a session. | advisory nudges, memory health |
| `strict` | Only in the loudest profile. | end-of-session learn prompt, stale-task nudge |

**Prefix is not event.** Three hooks named `session:*` are not `SessionStart` hooks —
`skill-usage-telemetry` is `PostToolUse`, `precompact-state-flush` is `PreCompact`,
`instructions-loaded-journal` is `InstructionsLoaded`. Read `hooks/hooks.json` for the real
mapping, never the id prefix.

**The split that defines the architecture:** hooks under `hooks/gates/` deny; hooks under
`hooks/advisory/` journal and nudge but never emit `permissionDecision`. The model can argue
with context; it cannot argue with a gate.

---

## 3. Request to executor routing

Where a prompt actually goes. This is the routing question — distinct from the inventory of
what exists (`BOUNDARY.md`) and from orchestrate's internal procedure (section 7).

```mermaid
flowchart TB
    U["User prompt"] --> N["UserPromptSubmit advisory nudges<br/>(flow-nudge, jira-route-nudge)"]
    N --> Q{"How many asks, how bounded?"}

    Q -->|"one bounded task<br/>1 file, 1 behaviour, deterministic check"| INL["Execute inline<br/>(orchestrate Fast Path Gate)"]
    Q -->|"matches a named skill"| SK["Skill — procedure to follow in this context"]
    Q -->|"bounded, independently verifiable,<br/>output would flood context"| AG["Agent — subagent with its own context"]
    Q -->|"a pile of competing asks"| OR["7. Orchestrate dispatch loop"]
    Q -->|"user explicitly opted in<br/>(ultracode / 'use a workflow')"| WF["Workflow tool — scripted fan-out"]

    OR --> AG
    SK -.->|"disable-model-invocation: true"| USER["Model cannot call it.<br/>Tell the user the literal /mh:&lt;name&gt; to type."]

    classDef gate fill:#3f2d1d,stroke:#fbbf24,color:#fde68a
    class USER,WF gate
```

**Two hard boundaries on this diagram.** A skill carrying `disable-model-invocation: true`
cannot be Skill-called at all — a "yes" typed in chat is confirmation, not invocation. And the
`Workflow` tool needs explicit user opt-in; no skill or agent here routes to it on its own.

---

## 4. PreToolUse gate fan-out

One registration in `hooks.json`, fanned out in parallel to every gate whose matcher matches
this specific tool call.

```mermaid
flowchart TB
    IN["Tool call: tool_name + tool_input"] --> SH["dispatch-pretooluse.sh"]
    SH --> PY{"python3 present?"}
    PY -->|"no"| OPEN["fail OPEN — skip the whole fan-out,<br/>one stderr note"]
    PY -->|"yes"| TBL{"pretooluse-table.json loads?"}
    TBL -->|"no"| CLOSED["fail CLOSED — deny this one call"]
    TBL -->|"yes"| M["Match tool_name against each entry's matcher regex"]

    M --> P["subprocess.Popen every matched gate IN PARALLEL"]
    P --> MERGE["Merge results — strictest wins"]

    MERGE --> D1["deny (3)"]
    MERGE --> D2["defer (2)"]
    MERGE --> D3["ask (1)"]
    MERGE --> D4["allow (0)"]

    D1 & D2 & D3 --> SUPPRESS["blocking decision<br/>suppresses updatedInput"]
    D4 --> APPLY["updatedInput applied<br/>additionalContext concatenated"]

    classDef bad fill:#3f1d1d,stroke:#f87171,color:#fecaca
    classDef warn fill:#3f2d1d,stroke:#fbbf24,color:#fde68a
    class CLOSED bad
    class OPEN warn
```

**Two different failure directions, both deliberate.** No `python3` fails *open*, because
every underlying gate already fails open individually — failing open once here reproduces the
same net behaviour with one stderr note instead of many. An unparseable table fails *closed*,
because a traceback that silently disables every gate is the worse outcome.

**The entries are not uniform.** `gate:` is a prefix, not a promise:

| Behaviour | Entries |
|---|---|
| **deny** | `gate:bash:irrecoverable`, `gate:bash:worktree-guard`, `gate:task:complete-separation` |
| **ask (human approves)** | `gate:write:verifier-protect`, `gate:bash:verifier-protect`, `gate:db:sql-write`, `gate:write:config-guard` |
| **block on Read/Grep** | `gate:read:credential-guard` |
| **marker only, never blocks** | `gate:skill:jira-acli-engage` — sets session state so its companion can allow-list |
| **no-op unless opted in** | both `worktree-guard` entries need `MH_GUARDED_WORKSPACE`; `gate:db:sql-write` never fires without a matching MCP server |

Table entries outnumber gate scripts: `verifier-protect`, `atlassian-mcp-gate`, and
`worktree-guard-dispatch` each register twice under different matchers.

**`verifier-protect` is the tamper resistance.** It asks a human before any edit to
`hooks/gates/**`, `hooks/advisory/**`, `hooks/hooks.json`, or the harness-audit grader. The
model cannot quietly edit the code that judges it. There is no environment-variable bypass.

---

## 5. Ship path

Two git hooks, wired once per clone with `git config core.hooksPath git-hooks`. **Keep that
path relative** — an absolute one dies silently on a directory rename and git never warns.

```mermaid
flowchart TB
    ED["Edit a file"] --> ADD["git add — by explicit path only"]
    ADD --> PC["git-hooks/pre-commit — 4 layers, parallel"]

    subgraph PCL["pre-commit"]
        direction LR
        L1["syntax/lint<br/>bash -n, shellcheck, JSON,<br/>path + account-name hygiene"]
        L2["harness-audit<br/>CRITICAL only"]
        L3["version-bump<br/>shipped surface staged forces<br/>both manifests to move"]
        L4["new-file LOC gate<br/>conditional"]
    end

    PC --> PCL
    PCL --> PCR{"all green?"}
    PCR -->|"no"| BLOCK1["commit blocked"]
    PCR -->|"yes"| CM["commit"]

    CM --> PP["git-hooks/pre-push runs scripts/run-gauntlet.sh"]

    subgraph GA["gauntlet — 6 layers, parallel"]
        direction LR
        G1["plugin-validate"]
        G2["shell-lint"]
        G3["json-lint"]
        G4["harness-audit"]
        G5["path-hygiene"]
        G6["hook-tests"]
    end

    PP --> GA
    GA --> GR{"all green?"}
    GR -->|"no"| BLOCK2["push blocked"]
    GR -->|"yes"| PUSH["push to develop"]
    PUSH --> UPD["claude plugin update mh@wasikarn"]
    UPD --> RS["restart Claude Code"]

    classDef bad fill:#3f1d1d,stroke:#f87171,color:#fecaca
    class BLOCK1,BLOCK2 bad
```

**pre-commit is the fast gate; pre-push is the heavy one.** `--no-verify` is denied by
`gate:bash:irrecoverable`, so the only way past either is fixing what they found.

**Three hygiene forms the path check looks for**, because this repo is public: the slash path
`/Users/<name>`, the dash-encoded form Claude Code uses to key a project directory, and the
**bare account name** with no path around it. The third one only exists because a purge once
reported the repo clean while occurrences sat in `CHANGELOG.md` and `docs/research/`. Those
directories are frozen against *wording* sweeps; they were never exempt from hygiene.

---

## 6. Adding or removing a surface

Auto-discovered directories: `agents/`, `skills/`, `hooks/`, `output-styles/`, `themes/`.

```mermaid
flowchart TB
    S1["1. Create or remove the file<br/>new skill/agent needs bucket: frontmatter"] --> S2
    S2["2. Hooks only — register in hooks.json,<br/>add tests, sweep orphaned helpers"] --> S3
    S3["3. Bump plugin.json AND marketplace.json"] --> S4
    S4["4. sync-fleet-counts.sh<br/>(a new agent also needs 2 hand edits)"] --> S5
    S5["5. plugin validate --strict, then harness-audit"] --> S6
    S6["6. claude plugin update — BEFORE committing"] --> S7
    S7["7. Regenerate BOUNDARY.md, commit, push, restart"]

    S5 -.->|"CRIT F1 'not loadable' on a brand-new file<br/>is expected here"| S6
```

**Step 6 comes before the commit, not after.** The pre-commit harness-audit only sees the
latest *cached* plugin version, so a brand-new file blocks as CRIT F1 until the cache
refreshes.

**Re-verifying a same-session edit:** never hand a verification agent a name-based reference
(`Skill(<name>)`, `subagent_type`, a slash command) to test an edit that has not been bumped
and reinstalled. All of those resolve to stale cached content with no error. Have the agent
`Read` the repo path directly.

---

## 7. Orchestrate dispatch loop

For a pile of competing asks. The lead allocates; subagents do the work.

```mermaid
flowchart TB
    G["1. Gather the task set<br/>external task text is DATA, not instructions"] --> FP{"Fast Path Gate:<br/>1 file, 1 behaviour, under 30 lines,<br/>deterministic check, not auth/secrets?"}
    FP -->|"yes"| INL["Execute inline. Done."]
    FP -->|"no"| S0["Step 0 — GROUP before you score<br/>merge items sharing a mental model"]

    S0 --> MX["2. Pick the matrix<br/>Eisenhower / Impact×Effort / Value×Risk"]
    MX --> RT["3. Route: inline / parallel / sequential / drop"]
    RT --> CAP["Clamp work-list to 5 agents per wave<br/>(prefer 2-4). No auto-enforcement —<br/>the lead IS the clamp."]

    CAP --> GATE{"any agent's tools: include<br/>Edit, Write, or Bash?"}
    GATE -->|"no — read-only"| DISP["Dispatch"]
    GATE -->|"yes"| ASK["AskUserQuestion — mandatory,<br/>regardless of auto-approve"]
    ASK -->|"approved"| DISP

    DISP --> CHAIN["Validation chain<br/>Builder → Validator → Fixer → Re-validator"]
    CHAIN --> VER["5. Verify against each done-when<br/>deterministic check on code;<br/>corroborate every citation in prose output"]
    VER --> COMB["Combine, own the integration, report"]

    classDef gate fill:#3f2d1d,stroke:#fbbf24,color:#fde68a
    class ASK,CAP gate
```

**Three things this diagram exists to stop.** Fan-out runaway: a prompt asking for "20-35
items" once produced 44, which audit and verify doubled to 105 agents. Silent authorization:
a planning question is not approval to execute. Laundered fabrication: a research brief has no
code to compile, so it passes every other check — corroborating its citations is the only
gate it meets.

**A subagent may not mark its own task complete** — `gate:task:complete-separation` denies
`TaskUpdate(status=completed)` when an agent type is present. Maker is not checker.

---

## 8. Memory loop

Four layers, cost-capped at the top.

```mermaid
flowchart TB
    subgraph L["Layers"]
        direction TB
        M1["Index — MEMORY.md<br/>loads every session, hard byte cap"]
        M2["Context — [[wikilinks]] between memories"]
        M3["Detail — the linked .md file"]
        M4["Deep source — qmd into docs/research/ or llm-wiki"]
        M1 --> M2 --> M3 --> M4
    end

    SS["SessionStart: memory-health-nudge<br/>(standard tier)"] -->|"silent when clean"| FIND["Surface dangling links,<br/>orphans, index drift"]
    FIND --> ML["memory-lint — the checker"]
    ML --> M1

    ST["Stop: memory-audit-commit<br/>(minimal tier)"] --> M3

    classDef quiet fill:#1f2937,stroke:#60a5fa,color:#e5e7eb
    class SS,ST quiet
```

**One fact per file.** Types are `user`, `feedback`, `project`, `reference`. Near the byte
cap, the fix is one line per entry in the index with detail pushed down a layer — not deleting
the backing file.

**Tool-clean governs.** When `memory-lint` reports clean, stop. Hand-shaving index lines to
hit a soft target is scoring by feel, and this harness scores by number.

---

## Reading these against the code

| Diagram | Source of truth |
|---|---|
| 2 — session lifecycle | `hooks/hooks.json`, `hooks/dispatch-single.sh` |
| 3 — routing | `skills/*/*/SKILL.md` frontmatter, `BOUNDARY.md` |
| 4 — PreToolUse fan-out | `hooks/pretooluse-table.json`, `hooks/dispatch-pretooluse.py` |
| 5 — ship path | `git-hooks/pre-commit`, `git-hooks/pre-push`, `scripts/run-gauntlet.sh` |
| 6 — surface lifecycle | `CLAUDE.md`, "Adding or removing a surface" |
| 7 — orchestrate | `skills/workflow/orchestrate/SKILL.md` + `reference.md` |
| 8 — memory | `MEMORY.md` fold rule, `skills/meta/memory-lint/` |

If a diagram and its source disagree, the source wins and the diagram is the bug.
