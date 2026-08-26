# Mermaid source for `docs/workflow-diagrams.md`

Reference snapshot of the 10 mermaid source blocks that `docs/workflow-diagrams.md`
used to inline. The HTML diagrams at `docs/diagrams/01..10-*.html` were redrawn
from this source by `docs/diagrams/src/build.py` (ship state v0.68.512).

When the HTML and this source disagree, the HTML wins — the source is a
reference, not a generator. To regenerate the HTML: edit `docs/diagrams/src/build.py`,
then run `python3 docs/diagrams/src/build.py`, then run `python3 docs/diagrams/src/check.py`.

## §1. What the plugin does → `docs/diagrams/01-overall.html`

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

## §2. Session lifecycle and hook dispatch → `docs/diagrams/02-session-lifecycle.html`

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

## §3. Advisory sensors → `docs/diagrams/03-advisory-sensors.html`

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

## §4. PreToolUse gate fan-out → `docs/diagrams/04-pretooluse-fanout.html`

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

## §5. Ship path → `docs/diagrams/05-ship-path.html`

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

## §6. Adding or removing a surface → `docs/diagrams/06-surface-lifecycle.html`

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

## §7. Orchestrate dispatch loop → `docs/diagrams/07-orchestrate.html`

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

## §8. Memory loop → `docs/diagrams/08-memory-loop.html`

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

## §9. Tiered pipeline → `docs/diagrams/09-tiered-pipeline.html`

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

## §10. Rule 14: the score-decision rubric → `docs/diagrams/10-score-decision.html`

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

