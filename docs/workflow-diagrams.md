# Workflow diagrams

Mermaid maps of what this plugin does and how each of its parts works. Section 1 covers the
plugin's own work. Claude Code's request lifecycle is the host's machinery this plugin
attaches to, and sections 2 onward take one piece of it at a time.

**Nothing here counts this plugin's surfaces.** You will not find a number of skills, agents,
or gate scripts in any diagram below, because no drift check watches this file and a
hand-typed number rots in silence. For the current inventory read `BOUNDARY.md`, which is
regenerated and drift-checked by harness-audit check 16. For the wiring read
`hooks/hooks.json` and `hooks/pretooluse-table.json`, the two files these diagrams were drawn
from. The event names in section 2 are the exception: those belong to Claude Code, not to this
plugin, so they do not drift when a surface is added.

---

## 1. What the plugin does

```mermaid
%%{init: {
  'theme':'base',
  'themeVariables': {
    'primaryColor':'#fcfcfa',
    'primaryBorderColor':'#ddddd6',
    'primaryTextColor':'#0f1718',
    'lineColor':'#65767a',
    'secondaryColor':'#dceff0',
    'tertiaryColor':'#e7edec',
    'fontFamily':'Source Serif 4, Charter, Georgia, serif',
    'fontSize':'15px'
  }
}}%%
flowchart TB
    subgraph BEFORE["1 · Session starts: what the plugin puts in place"]
        direction LR
        D["Doctrine injection<br/>METHODOLOGY, every start"]
        SU["Skills and agents<br/>from the versioned cache"]
    end
    subgraph DURING["2 · The model acts: what the plugin does about it"]
        direction LR
        G["Deny gates<br/>the irrecoverable set"]
        SE["Advisory sensors<br/>journal, never block"]
    end
    subgraph AFTER["3 · Work ships: what grades it"]
        direction LR
        V["Deterministic verifiers<br/>harness-audit, gauntlet"]
        B["Version bump<br/>a change lands next session"]
    end

    BEFORE --> DURING --> AFTER

    classDef det fill:#1f2937,stroke:#60a5fa,color:#e5e7eb
    class G,V det
```

**This diagram is mirrored in `README.md`'s How it runs section. Edit both or neither.**
Nothing checks the pair; it is two files kept in sync by hand.

This is the plugin's own work, not Claude Code's. The three bands are the moments the plugin
acts on a session. The host's request lifecycle starts in section 2. The two nodes drawn with
the dark fill carry the design: the model is the maker, and every box that can stop it is
deterministic shell. Maker is not checker.

The loop closes at the version bump, which is why it sits last instead of first. A change to a
shipped surface reaches the next session, and the session that made it keeps running on the
old cached copy. Same-version edits are silent no-ops, and that is the most common way work
here looks done without being done.

---

## 2. Session lifecycle and hook dispatch

Claude Code fires nine events that this plugin listens for. Every one except `PreToolUse` goes
through `hooks/dispatch-single.sh`, a filter that can drop the hook before its real script ever
runs.

```mermaid
%%{init: {
  'theme':'base',
  'themeVariables': {
    'primaryColor':'#fcfcfa',
    'primaryBorderColor':'#ddddd6',
    'primaryTextColor':'#0f1718',
    'lineColor':'#65767a',
    'secondaryColor':'#dceff0',
    'tertiaryColor':'#e7edec',
    'fontFamily':'Source Serif 4, Charter, Georgia, serif',
    'fontSize':'15px'
  }
}}%%
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
    K -->|"yes"| X["exit 0, the hook never runs"]
    K -->|"no"| T{"tier at or below MH_HOOK_PROFILE?"}
    T -->|"no"| X
    T -->|"yes"| R["exec the real script"]

    classDef drop fill:#3f1d1d,stroke:#f87171,color:#fecaca
    class X drop
```

**Tiers are ordinal:** `minimal(0) < standard(1) < strict(2)`. A hook fires when its own tier
sits at or below the active profile. `MH_HOOK_PROFILE` defaults to `strict`. An unset
environment runs everything. The filter exists to quiet a session down when you want it
quieter.

What each tier means in practice:

| Tier | Behaviour | Typical carrier |
|---|---|---|
| `minimal` | Always on. Turning it off costs you functionality, not noise. | doctrine injection, env-var anchor, cost tracking |
| `standard` | On by default, first thing dropped when quieting a session. | advisory nudges, memory health |
| `strict` | Only in the loudest profile. | end-of-session learn prompt, stale-task nudge |

**Read the event from `hooks.json`, never from the hook id.** Three hooks named `session:*`
listen on something else entirely: `skill-usage-telemetry` is `PostToolUse`,
`precompact-state-flush` is `PreCompact`, `instructions-loaded-journal` is
`InstructionsLoaded`. The prefix says where a hook came from, and the JSON says when it fires.

**Where the deny/advise split lives:** hooks under `hooks/gates/` deny. Hooks under
`hooks/advisory/` journal and nudge, and they never emit `permissionDecision`. The model can
argue with context. It cannot argue with a gate.

---

## 3. Advisory sensors, and what happens instead of blocking

The advise half of the operating model. Section 4 is the deny half. Seven sensors watch four
events, and grep confirms that none of them emits `permissionDecision`.

```mermaid
%%{init: {
  'theme':'base',
  'themeVariables': {
    'primaryColor':'#fcfcfa',
    'primaryBorderColor':'#ddddd6',
    'primaryTextColor':'#0f1718',
    'lineColor':'#65767a',
    'secondaryColor':'#dceff0',
    'tertiaryColor':'#e7edec',
    'fontFamily':'Source Serif 4, Charter, Georgia, serif',
    'fontSize':'15px'
  }
}}%%
flowchart LR
    E1["UserPromptSubmit<br/>flow-nudge · jira-route"] --> S
    E2["PostToolUse<br/>loop · plan · compliance"] --> S
    E3["PostToolUseFailure<br/>mcp-failure-nudge"] --> S
    E4["SessionEnd<br/>learn-nudge"] --> S
    S["Advisory sensors<br/>read, count, journal"]
    S --> C["Context into the turn<br/>the model may ignore it"]
    S --> D["State on disk<br/>~/.local/share/"]

    classDef det fill:#1f2937,stroke:#60a5fa,color:#e5e7eb
    class C det
```

**A sensor produces two things, and a verdict is neither of them.** It can put text into the
turn for the model to weigh or ignore, and it can leave state on disk so the next turn knows
what the last one did. That is the entire contract.

**Why the split is load-bearing.** A gate is a verifier: deterministic shell returning a score
something else can branch on. A sensor is an observer. Blur the two and you put a model in the
position of grading its own work. Maker is not checker. Sensors journal and nudge; the gates
in section 4 are the only things that stop anything.

**The sensors measure; they do not conclude.** `loop-repeat-nudge` counts identical
`{tool, params}` pairs and leaves the reading there, without deciding whether a session is
spinning. `mcp-failure-nudge` observes failures Claude Code already surfaced and never probes a
server itself. A sensor that concluded would be a gate wearing the wrong label.

---

## 4. PreToolUse gate fan-out

One registration in `hooks.json`, fanned out in parallel to every gate whose matcher matches
this specific tool call.

```mermaid
%%{init: {
  'theme':'base',
  'themeVariables': {
    'primaryColor':'#fcfcfa',
    'primaryBorderColor':'#ddddd6',
    'primaryTextColor':'#0f1718',
    'lineColor':'#65767a',
    'secondaryColor':'#dceff0',
    'tertiaryColor':'#e7edec',
    'fontFamily':'Source Serif 4, Charter, Georgia, serif',
    'fontSize':'15px'
  }
}}%%
flowchart TB
    IN["Tool call: tool_name + tool_input"] --> SH["dispatch-pretooluse.sh"]
    SH --> PY{"python3 present?"}
    PY -->|"no"| OPEN["fail OPEN: skip the whole fan-out,<br/>one stderr note"]
    PY -->|"yes"| TBL{"pretooluse-table.json loads?"}
    TBL -->|"no"| CLOSED["fail CLOSED: deny this one call"]
    TBL -->|"yes"| M["Match tool_name against each entry's matcher regex"]

    M --> P["Run every matched gate as its own process, in parallel"]
    P --> MERGE["Merge results, strictest wins"]

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

**Two failure directions, both chosen on purpose.** A missing `python3` fails open: every
underlying gate already fails open on its own, so failing open once here produces the same
net behaviour with one stderr note instead of many. An unparseable table fails closed. The
alternative is a traceback that quietly disables every gate at once, which is the worse
outcome.

**The entries do not all behave alike.** `gate:` is a prefix, not a promise:

| Behaviour | Entries |
|---|---|
| **deny** | `gate:bash:irrecoverable`, `gate:bash:worktree-guard`, `gate:task:complete-separation` |
| **ask (human approves)** | `gate:write:verifier-protect`, `gate:bash:verifier-protect`, `gate:db:sql-write`, `gate:write:config-guard` |
| **block on Read/Grep** | `gate:read:credential-guard` |
| **marker only, never blocks** | `gate:skill:jira-acli-engage`, which sets session state so its companion can allow-list |
| **no-op unless opted in** | both `worktree-guard` entries need `MH_GUARDED_WORKSPACE`; `gate:db:sql-write` stays quiet without a matching MCP server |

Table entries outnumber gate scripts, because `verifier-protect`, `atlassian-mcp-gate`, and
`worktree-guard-dispatch` each register twice under different matchers.

**`verifier-protect` is the tamper resistance.** It asks a human before any edit to
`hooks/gates/**`, `hooks/advisory/**`, `hooks/hooks.json`, or the harness-audit grader. The
model cannot quietly edit the code that judges it, and there is no environment-variable bypass.

---

## 5. Ship path

Two git hooks, wired once per clone with `git config core.hooksPath git-hooks`. **Keep that
path relative.** An absolute path dies the moment the directory is renamed. Git says nothing;
it just runs no hooks at all.

```mermaid
%%{init: {
  'theme':'base',
  'themeVariables': {
    'primaryColor':'#fcfcfa',
    'primaryBorderColor':'#ddddd6',
    'primaryTextColor':'#0f1718',
    'lineColor':'#65767a',
    'secondaryColor':'#dceff0',
    'tertiaryColor':'#e7edec',
    'fontFamily':'Source Serif 4, Charter, Georgia, serif',
    'fontSize':'15px'
  }
}}%%
flowchart TB
    ED["Edit a file"] --> ADD["git add, each path named"]
    ADD --> PC["git-hooks/pre-commit runs 4 layers in parallel"]

    subgraph PCL["pre-commit"]
        direction LR
        L1["syntax/lint<br/>bash -n, shellcheck, JSON,<br/>path + account-name hygiene"]
        L2["harness-audit<br/>CRITICAL only"]
        L3["version-bump<br/>a staged shipped surface forces<br/>both manifests to move"]
        L4["new-file LOC gate<br/>conditional"]
    end

    PC --> PCL
    PCL --> PCR{"all green?"}
    PCR -->|"no"| BLOCK1["commit blocked"]
    PCR -->|"yes"| CM["commit"]

    CM --> PP["git-hooks/pre-push runs scripts/run-gauntlet.sh"]

    subgraph GA["gauntlet: 6 layers in parallel"]
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

**pre-commit is the fast gate and pre-push is the heavy one.** The skip flag is denied by
`gate:bash:irrecoverable`, so the way past either one is to fix what it found.

**The path check looks for three hygiene forms**, because this repo is public. The slash path
`/Users/<name>`, the dash-encoded form Claude Code uses to key a project directory, and the
bare account name sitting in prose with no path around it. The third form exists because a
purge once reported the repo clean while occurrences sat in `CHANGELOG.md` and
`docs/research/`. Those directories are frozen against wording sweeps, and a wording carve-out
was read as a hygiene carve-out.

---

## 6. Adding or removing a surface

Auto-discovered directories: `agents/`, `skills/`, `hooks/`, `output-styles/`, `themes/`.

```mermaid
%%{init: {
  'theme':'base',
  'themeVariables': {
    'primaryColor':'#fcfcfa',
    'primaryBorderColor':'#ddddd6',
    'primaryTextColor':'#0f1718',
    'lineColor':'#65767a',
    'secondaryColor':'#dceff0',
    'tertiaryColor':'#e7edec',
    'fontFamily':'Source Serif 4, Charter, Georgia, serif',
    'fontSize':'15px'
  }
}}%%
flowchart TB
    S1["1. Create or remove the file<br/>a new skill or agent needs bucket: frontmatter"] --> S2
    S2["2. Hooks only: register in hooks.json,<br/>add tests, sweep orphaned helpers"] --> S3
    S3["3. Bump plugin.json and marketplace.json together"] --> S4
    S4["4. sync-fleet-counts.sh<br/>(a new agent also needs 2 hand edits)"] --> S5
    S5["5. plugin validate --strict, then harness-audit"] --> S6
    S6["6. claude plugin update<br/>run this before committing"] --> S7
    S7["7. Regenerate BOUNDARY.md, commit, push, restart"]

    S5 -.->|"a brand-new file reads as<br/>CRIT F1 'not loadable' here"| S6
```

**Step 6 runs before the commit.** The pre-commit harness-audit only sees the latest cached
plugin version, so a brand-new file keeps blocking as CRIT F1 until the cache catches up.

**Re-verifying a same-session edit:** never hand a verification agent a name-based reference
like `Skill(<name>)`, a `subagent_type`, or a slash command to test an edit that has not been
bumped and reinstalled. Every one of those resolves to stale cached content and reports no
error while doing it. Have the agent `Read` the repo path directly.

---

## 7. Orchestrate dispatch loop

For a pile of competing asks. The lead allocates and subagents do the work.

```mermaid
%%{init: {
  'theme':'base',
  'themeVariables': {
    'primaryColor':'#fcfcfa',
    'primaryBorderColor':'#ddddd6',
    'primaryTextColor':'#0f1718',
    'lineColor':'#65767a',
    'secondaryColor':'#dceff0',
    'tertiaryColor':'#e7edec',
    'fontFamily':'Source Serif 4, Charter, Georgia, serif',
    'fontSize':'15px'
  }
}}%%
flowchart TB
    G["1. Gather the task set<br/>text from a tracker is data, never instructions"] --> FP{"Fast Path Gate:<br/>1 file, 1 behaviour, under 30 lines,<br/>deterministic check, not auth/secrets?"}
    FP -->|"yes"| INL["Execute inline. Done."]
    FP -->|"no"| MX["2. Prioritise<br/>Step 0 first: group items that share a mental model,<br/>then score on Eisenhower / Impact×Effort / Value×Risk"]

    MX --> RT["3. Route each item:<br/>inline, parallel, sequential, or drop"]
    RT --> CAP["Clamp the work-list to 5 agents per wave<br/>(prefer 2-4). Nothing enforces this<br/>but the lead."]

    CAP --> GATE{"any agent's tools: include<br/>Edit, Write, or Bash?"}
    GATE -->|"read-only"| DISP["4. Propose, then dispatch"]
    GATE -->|"yes"| ASK["AskUserQuestion, mandatory<br/>whatever the auto-approve setting says"]
    ASK -->|"approved"| DISP

    DISP --> CHAIN["Validation chain<br/>builder, validator, fixer, re-validator"]
    CHAIN --> VER["5. Verify against each done-when<br/>deterministic check on code;<br/>corroborate every citation in prose output"]
    VER --> COMB["Combine, own the integration, report"]

    classDef gate fill:#3f2d1d,stroke:#fbbf24,color:#fde68a
    class ASK,CAP gate
```

**One incident and two risks this shape guards against.** The incident: a prompt asking for
"20-35 items" once produced 44, which audit and verify doubled to 105 agents, which is where
the hard cap of 5 comes from. The two risks are silent authorization, where a planning
question gets read as approval to execute, and laundered fabrication, where a research brief
has no code to compile and so slides past every check except corroborating its citations.

**A subagent may not mark its own task complete.** `gate:task:complete-separation` denies
`TaskUpdate(status=completed)` when an agent type is present. Maker is not checker.

---

## 8. Memory loop

Four layers, cost-capped at the top.

```mermaid
%%{init: {
  'theme':'base',
  'themeVariables': {
    'primaryColor':'#fcfcfa',
    'primaryBorderColor':'#ddddd6',
    'primaryTextColor':'#0f1718',
    'lineColor':'#65767a',
    'secondaryColor':'#dceff0',
    'tertiaryColor':'#e7edec',
    'fontFamily':'Source Serif 4, Charter, Georgia, serif',
    'fontSize':'15px'
  }
}}%%
flowchart TB
    subgraph L["Layers"]
        direction TB
        M1["Index: MEMORY.md<br/>loads every session, hard byte cap"]
        M2["Context: [[wikilinks]] between memories"]
        M3["Detail: the linked .md file"]
        M4["Deep source: qmd search<br/>docs/research · llm-wiki"]
        M1 --> M2 --> M3 --> M4
    end

    SS["SessionStart: memory-health-nudge<br/>(standard tier)"] -->|"silent when clean"| FIND["Surface dangling links,<br/>orphans, index drift"]
    FIND --> ML["memory-lint, the checker"]
    ML --> M1

    ST["Stop: memory-audit-commit<br/>(minimal tier)"] --> M3

    classDef quiet fill:#1f2937,stroke:#60a5fa,color:#e5e7eb
    class SS,ST quiet
```

**One fact per file.** Types are `user`, `feedback`, `project`, `reference`. Near the byte cap
the fix is one line per entry in the index with the detail pushed down a layer, and the backing
file stays where it is.

**Tool-clean governs.** When `memory-lint` reports clean, stop. Hand-shaving index lines to hit
a soft target is scoring by feel, and this harness scores by number.

---

## 9. Tiered pipeline

The headline multi-model review loop. Four stages, each fenced by a shell script that holds
the boundary.

```mermaid
%%{init: {
  'theme':'base',
  'themeVariables': {
    'primaryColor':'#fcfcfa',
    'primaryBorderColor':'#ddddd6',
    'primaryTextColor':'#0f1718',
    'lineColor':'#65767a',
    'secondaryColor':'#dceff0',
    'tertiaryColor':'#e7edec',
    'fontFamily':'Source Serif 4, Charter, Georgia, serif',
    'fontSize':'15px'
  }
}}%%
flowchart TB
    S1["Fable plans"] --> S2["Sonnet executes"]
    S2 --> S3["Opus reviews<br/>fix loop, cap 3"]
    S3 --> S4["Fable re-reviews<br/>triage-gated"]
    S1 -.->|"prompt-only"| S2
    S2 -.->|"prompt-only"| S3
    S3 -.->|"counted in code"| S4

    classDef gate fill:#1f2937,stroke:#60a5fa,color:#e5e7eb
    class S3,S4 gate
```

**Structured but prompt-only.** Model selection is prompt-only — no script enforces which
tier runs at each stage. The fix loop is counted in code at three retries; everything else
(which model, when to triage) is discretionary. Same maker-not-checker rule as the gates: a
script can count, but it cannot pick.

The boundary that is fenced is the one that bites: three retries is the cap, so an Opus review
loop cannot run forever. That is a deterministic shell guarding a model call.

---

## 10. Rule 14: the score-decision rubric

A formal decision verdict: stated criteria + weights + numeric result + pass/fail +
confidence. A pass threshold AND a fatal-weakness floor must both hold. Precedent is queried
first.

```mermaid
%%{init: {
  'theme':'base',
  'themeVariables': {
    'primaryColor':'#fcfcfa',
    'primaryBorderColor':'#ddddd6',
    'primaryTextColor':'#0f1718',
    'lineColor':'#65767a',
    'secondaryColor':'#dceff0',
    'tertiaryColor':'#e7edec',
    'fontFamily':'Source Serif 4, Charter, Georgia, serif',
    'fontSize':'15px'
  }
}}%%
flowchart TB
    D["Decision?"] --> C1["Criterion 1<br/>alignment with stated goal"]
    D --> C2["Criterion 2<br/>evidence for the claim"]
    D --> C3["Criterion 3<br/>risk under the chosen path"]
    D --> C4["Criterion 4<br/>cost of being wrong"]
    C1 & C2 & C3 & C4 --> F["Fatal-weakness floor<br/>must hold regardless of total score"]

    classDef gate fill:#3f2d1d,stroke:#fbbf24,color:#fde68a
    class F gate
```

**Structured but prompt-only.** No script enforces model choice, the weights, or the floor.
The rubric gives a defensible structure for a decision the model is about to make anyway;
what it cannot do is veto the model. Same honesty as the gates: a script can score, but it
cannot reason.

The floor sits below the criteria because the criteria are negotiable; the floor is not. A
decision with a high total score and a failed floor is still a failure.

---

## Reading these against the code

| Diagram | Source of truth |
|---|---|
| 2. session lifecycle | `hooks/hooks.json`, `hooks/dispatch-single.sh` |
| 3. advisory sensors | `hooks/advisory/*.sh`, `hooks/hooks.json` |
| 4. PreToolUse fan-out | `hooks/pretooluse-table.json`, `hooks/dispatch-pretooluse.py` |
| 5. ship path | `git-hooks/pre-commit`, `git-hooks/pre-push`, `scripts/run-gauntlet.sh` |
| 6. surface lifecycle | `CLAUDE.md`, "Adding or removing a surface" |
| 7. orchestrate | `skills/workflow/orchestrate/SKILL.md` and `reference.md` |
| 8. memory | `MEMORY.md` fold rule, `skills/meta/memory-lint/` |
| 9. tiered pipeline | `skills/workflow/tiered-pipeline/SKILL.md` |
| 10. score-decision | `skills/meta/score-decision/SKILL.md`, `docs/METHODOLOGY.md` Rule 14 |

When a diagram and its source disagree, the source wins and the diagram is the bug.

**Presentation copies:** `docs/diagrams/01..10` hold the same ten diagrams as inline SVG in
the diagram-design default editorial skin. Open one in a browser. They are generated, so edit
`docs/diagrams/src/` and run `build.py`, never the HTML; `check.py` next to it verifies
geometry and text fit. The mermaid above stays because GitHub renders it inline and the HTML
files do not. Two representations, kept in sync by hand, with nothing checking the pair.
