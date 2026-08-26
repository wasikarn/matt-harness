import sys; sys.path.insert(0,'.')
from dd import *
import pathlib
OUT=str(pathlib.Path(__file__).resolve().parent.parent)+"/"   # docs/diagrams/, next to src/
EY="mh@wasikarn · Diagram Design"
made=[]

# ---------------------------------------------------------------- 1. overall
# The plugin's own work. Claude Code's request lifecycle is sections 2 onward.
p=[]
p.append(line(240,140,304,140)); p.append(line(584,140,616,140))
p.append(line(240,300,304,300)); p.append(line(584,300,616,300))
p.append(line(240,460,304,460)); p.append(line(584,460,616,460))
p.append(line(140,168,140,272)); p.append(line(140,328,140,432))
p.append(hvh(896,460,896,140,920,dash=True))          # ships to the NEXT session, not this one
p.append(vlabel(920,380,"NEXT SESSION",left=True,w=80))
p.append(node(40,112,200,56,"Session starts","",kind="input"))
p.append(node(40,272,200,56,"The model acts","",kind="input"))
p.append(node(40,432,200,56,"Work ships","",kind="input"))
p.append(node(304,112,280,56,"Doctrine injection","METHODOLOGY, every start"))
p.append(node(616,112,280,56,"Skills and agents","from the versioned cache"))
p.append(node(304,272,280,56,"Deny gates","the irrecoverable set",kind="focal"))
p.append(node(616,272,280,56,"Advisory sensors","journal, never block"))
p.append(node(304,432,280,56,"Deterministic verifiers","harness-audit · gauntlet",kind="focal"))
p.append(node(616,432,280,56,"Version bump","a change lands next session"))
p.append(legend(540,"LEGEND · CORAL BOXES ARE SHELL, NOT MODELS",[
  (40,"input","The session's own moment"),(240,"step","What the plugin adds"),
  (440,"focal","Deterministic shell"),(740,"arrow-dash","Lands next session")]))
made.append(page(OUT+"01-overall.html","overall",EY,"What the plugin does to a session",
  "Map of the three moments this plugin acts on a Claude Code session: putting doctrine and surfaces in place before, denying the irrecoverable and journalling the rest while the model works, and grading the result with deterministic verifiers whose changes only reach the next session.",p,note='The model is the maker. Every coral box on this page is shell, which is why a gate is never a model and a verifier is never a model: a model grading its own output is two optimists agreeing.'))

# --------------------------------------------------- 2. session lifecycle
p=[]
p.append(line(192,112,240,112)); p.append(line(400,112,488,112))
p.append(hlabel(444,112,"YES"))
p.append(line(320,156,320,204)); p.append(vlabel(320,180,"NO",w=24))
p.append(line(320,260,320,304))
p.append(line(416,352,536,352)); p.append(hlabel(476,352,"FILTERED"))
p.append(line(320,400,320,440,accent=True)); p.append(vlabel(320,420,"FIRES",accent=True))
p.append(oval(40,84,152,56,"Lifecycle event","9 events wired",kind="input"))
p.append(diamond(320,112,80,44,["PreToolUse?"]))
p.append(node(488,84,216,56,"Gate fan-out","its own dispatcher",kind="ext"))
p.append(node(232,204,176,56,"dispatch-single.sh","id · tier · script"))
p.append(diamond(320,352,96,48,["Disabled, or tier","above the profile?"]))
p.append(node(536,324,216,56,"Never runs","exits 0, prints nothing",kind="ext"))
p.append(node(232,440,176,56,"Hook script runs","",kind="focal"))
p.append(legend(540,"LEGEND · TIERS RANK MINIMAL < STANDARD < STRICT",[
  (40,"input","Event"),(160,"step","Step"),(280,"ext","Not this path"),
  (440,"focal","The hook fires"),(640,"arrow-accent","Passes the filter")]))
made.append(page(OUT+"02-session-lifecycle.html","lifecycle",EY,"Session lifecycle and hook dispatch",
  "Flowchart showing every non-PreToolUse hook passing through dispatch-single.sh, where a kill-switch entry or a tier above the active profile silently drops it before its script runs.",p,note='Tiers are ordinal, minimal(0) < standard(1) < strict(2). A hook fires when its own tier sits at or below MH_HOOK_PROFILE, which defaults to strict, so an unset environment runs everything.'))

# --------------------------------------------------- 3. advisory sensors
# The advise half of the operating model. 04 is the deny half.
p=[]
for cy in (126,202,278,354):
    p.append(line(288,cy,376,cy))                     # straight in: the lane spans every row
p.append(line(600,172,680,172)); p.append(line(600,340,680,340))
p.append(hlabel(640,172,"NO DECISION",w=72))
p.append(node(40,100,248,52,"UserPromptSubmit","flow · jira-route",kind="input"))
p.append(node(40,176,248,52,"PostToolUse","loop · plan-review · compliance",kind="input"))
p.append(node(40,252,248,52,"PostToolUseFailure","mcp-failure",kind="input"))
p.append(node(40,328,248,52,"SessionEnd","learn",kind="input"))
p.append(node(376,100,224,308,"Advisory sensors","read, count, journal"))
p.append(node(680,140,240,64,"Context into the turn","the model may ignore it",kind="focal"))
p.append(node(680,308,240,64,"State on disk","~/.local/share/",kind="ext"))
p.append(legend(540,"LEGEND · SENSORS OBSERVE, GATES DECIDE",[
  (40,"input","Event observed"),(200,"step","Where the sensors live"),
  (400,"focal","What reaches the model"),(620,"ext","What survives the session")]))
made.append(page(OUT+"03-advisory-sensors.html","advisory",EY,"What the advisory sensors do instead of blocking",
  "Data flow showing the four events this plugin's advisory sensors observe and the two things they produce. Context the model is free to ignore, and state on disk, but never a permission decision.",p,note='Not one sensor under hooks/advisory/ emits permissionDecision, and grep is what confirms it. Deciding belongs to the gates, drawn in section 4 of docs/workflow-diagrams.md.'))

# --------------------------------------------------- 4. pretooluse fan-out
p=[]
p.append(line(208,96,264,96)); p.append(line(424,96,496,96)); p.append(hlabel(460,96,"NO",w=24))
p.append(line(344,136,344,176)); p.append(vlabel(344,160,"YES",w=28))
p.append(line(424,216,496,216,accent=True)); p.append(hlabel(460,216,"NO",accent=True,w=24))
p.append(line(344,256,344,308)); p.append(vlabel(344,286,"YES",w=28))
p.append(line(432,336,536,336))
p.append(line(584,364,584,428)); p.append(vlabel(584,400,"DENY / ASK",w=64,left=True))
p.append(line(704,364,704,428)); p.append(vlabel(704,400,"ALLOW",w=40))
p.append(oval(40,68,168,56,"Tool call","tool_name + input",kind="input"))
p.append(diamond(344,96,80,40,["python3 present?"]))
p.append(node(496,68,216,56,"Fail OPEN","no gate runs at all",kind="ext"))
p.append(diamond(344,216,80,40,["Table parses?"]))
p.append(node(496,188,216,56,"Fail CLOSED","deny this one call",kind="ext"))
p.append(node(256,308,176,56,"Match, then run","every gate, in parallel"))
p.append(node(536,308,200,56,"Merge","strictest wins",kind="focal"))
p.append(node(440,428,216,56,"Blocked","updatedInput dropped",kind="ext"))
p.append(node(696,428,224,56,"Allowed","input + context applied",kind="ext"))
p.append(legend(540,"LEGEND · STRICTEST WINS: DENY 3 > DEFER 2 > ASK 1 > ALLOW 0",[
  (40,"input","Tool call"),(170,"step","Step"),(290,"ext","Outcome"),
  (410,"focal","Where verdicts merge"),(590,"arrow-accent","Fails closed on purpose")]))
made.append(page(OUT+"04-pretooluse-fanout.html","fanout",EY,"PreToolUse gate fan-out",
  "Flowchart showing one hook registration fanning out in parallel to every matching gate, merging their verdicts strictest-first, and failing open without python3 but closed on an unparseable table.",p,note='Verdicts merge strictest-first: deny 3, defer 2, ask 1, allow 0. A missing python3 fails the whole fan-out open, because every gate already fails open on its own. An unparseable table fails it closed.'))

# --------------------------------------------------- 5. ship path
p=[]
for y in (92,172,252,332):
    p.append(line(480,y,480,y+28,accent=(y==332)))
p.append(line(480,412,480,440,accent=True))
p.append(vlabel(480,110,"BY PATH ONLY",w=76))
p.append(vlabel(480,270,"PASS",w=32))
p.append(vlabel(480,430,"PASS",accent=True,w=32))
p.append(line(616,226,680,226,dash=True)); p.append(hlabel(648,226,"FAIL",w=32))
p.append(line(616,386,680,386,dash=True)); p.append(hlabel(648,386,"FAIL",w=32))
p.append(oval(344,40,272,52,"Edit a file","",kind="input"))
p.append(node(344,120,272,52,"git add","each path named"))
p.append(node(344,200,272,52,"pre-commit","syntax · audit · version · LOC"))
p.append(node(344,280,272,52,"commit",""))
p.append(node(344,360,272,52,"pre-push gauntlet","6 layers, in parallel",kind="focal"))
p.append(node(344,440,272,52,"push, update, restart",""))
p.append(node(680,200,232,52,"Commit blocked","fix it or it stays blocked",kind="ext"))
p.append(node(680,360,232,52,"Push blocked","the log names the layer",kind="ext"))
p.append(legend(540,"LEGEND · KEEP CORE.HOOKSPATH RELATIVE",[
  (40,"input","Working tree"),(180,"step","Stage"),(290,"ext","Blocked"),
  (400,"focal","The heavy gate"),(600,"arrow-dash","Gate rejects")]))
made.append(page(OUT+"05-ship-path.html","ship",EY,"The ship path and its two gates",
  "Process showing an edit passing the fast pre-commit gate and then the full pre-push gauntlet before it can reach the remote and the plugin cache.",p,note='Keep core.hooksPath relative. An absolute path dies the moment the directory is renamed, and git never warns you; it just runs no hooks at all.'))

# --------------------------------------------------- 6. surface lifecycle
p=[]
for x in (240,464,688):
    p.append(line(x,188,x+24,188))
p.append(line(812,220,812,356))
p.append(line(712,388,688,388)); p.append(line(488,388,464,388))
STEPS=[(40,156,"Create the file","bucket: frontmatter","01"),
       (264,156,"Wire the hook","hooks.json + tests","02"),
       (488,156,"Bump both manifests","plugin + marketplace","03"),
       (712,156,"Sync fleet counts","sync-fleet-counts.sh","04"),
       (712,356,"Validate and audit","plugin validate + audit.sh","05"),
       (488,356,"claude plugin update","BEFORE the commit","06"),
       (264,356,"Regen, commit, restart","BOUNDARY.md last","07")]
for x,y,name,sub,n in STEPS:
    p.append(steptag(x,y,n))
    p.append(node(x,y,200,64,name,sub,kind=("focal" if n=="06" else "step")))
p.append(legend(540,"LEGEND · STEP 06 REFRESHES THE CACHE FIRST",[
  (40,"step","Ordered step"),(200,"focal","Runs before the commit"),
  (440,"arrow","Sequence")]))
made.append(page(OUT+"06-surface-lifecycle.html","surface",EY,"Adding or removing a surface",
  "Seven ordered steps for adding a plugin surface, with the cache refresh landing at step six, before the commit.",p,note='A brand-new file reads as CRIT F1, not loadable, until step 06 refreshes the cache. That is why the plugin update runs before the commit.'))

# --------------------------------------------------- 7. orchestrate
p=[]
p.append(line(176,84,216,84)); p.append(line(376,84,496,84)); p.append(hlabel(436,84,"FAST PATH"))
p.append(line(296,124,296,168)); p.append(vlabel(296,148,"NO",w=24))
p.append(line(296,224,296,256)); p.append(line(296,312,296,344))
p.append(line(392,372,472,372)); p.append(hlabel(432,372,"ONE WAVE"))
p.append(line(648,372,712,372,accent=True)); p.append(hlabel(680,372,"WRITES",accent=True,w=44))
p.append(line(560,412,560,456)); p.append(vlabel(560,436,"READ-ONLY",w=64))
p.append(vhv(816,400,640,456,428,accent=True))
p.append(oval(32,56,144,56,"Task set","",kind="input"))
p.append(diamond(296,84,80,40,["Fast path gate?"]))
p.append(node(496,56,200,56,"Execute inline","no orchestration",kind="ext"))
p.append(node(200,168,192,56,"Group first","shared mental model"))
p.append(node(200,256,192,56,"Score, then route"))
p.append(node(200,344,192,56,"Clamp to 5","the lead is the clamp",kind="focal"))
p.append(diamond(560,372,88,40,["Write tools?"]))
p.append(node(712,344,208,56,"AskUserQuestion","always mandatory"))
p.append(node(456,456,256,56,"The validation chain","builder · validator · fixer · re-validator"))
p.append(legend(540,"LEGEND · FIVE AGENTS PER WAVE, HARD CAP",[
  (40,"input","Work in"),(150,"step","Lead's step"),(280,"ext","Not orchestrated"),
  (430,"focal","The hard cap"),(620,"arrow-accent","Needs approval")]))
made.append(page(OUT+"07-orchestrate.html","orchestrate",EY,"The orchestrate dispatch loop",
  "Flowchart showing a pile of tasks grouped and scored, clamped to five agents per wave, gated on human approval whenever an agent can write, and run through a builder-validator chain.",p,note='Five agents per wave is a hard cap, and nothing but the lead enforces it. A subagent may not mark its own task complete either: gate:task:complete-separation denies that. Maker is not checker.'))

# --------------------------------------------------- 8. memory loop
p=[]
p.append(line(248,176,288,176))
p.append(line(712,176,672,176))
p.append(vh(816,208,672,352,dash=True)); p.append(vlabel(816,322,"READS",w=44,left=True))
for y in (208,296,384):
    p.append(line(480,y,480,y+24))
p.append(node(40,144,208,64,"SessionStart nudge","silent when clean",kind="input"))
p.append(node(288,144,384,64,"Index: MEMORY.md","every session, under a byte cap"))
p.append(node(288,232,384,64,"Context: [[wikilinks]]","how memories reach each other",kind="store"))
p.append(node(288,320,384,64,"Detail: one fact per file","user · feedback · project · reference",kind="store"))
p.append(node(288,408,384,64,"Deep source","qmd → docs/research, llm-wiki",kind="ext"))
p.append(node(712,144,208,64,"memory-lint","the checker",kind="focal"))
p.append(legend(540,"LEGEND · WHEN MEMORY-LINT REPORTS CLEAN, STOP",[
  (40,"input","Surfacing hook"),(190,"step","Loaded layer"),(330,"store","Traversed layer"),
  (490,"ext","Last resort"),(610,"focal","The checker")]))
made.append(page(OUT+"08-memory-loop.html","memory",EY,"The memory loop",
  "Layer stack from the session-loaded index down through wikilinks and per-fact detail files to deep sources, with memory-lint as the checker that decides when it is clean.",p,note='When memory-lint reports clean, stop. Hand-shaving index lines to hit a soft target is scoring by feel, and this harness scores by number.'))

for m in made: print("wrote", m)
