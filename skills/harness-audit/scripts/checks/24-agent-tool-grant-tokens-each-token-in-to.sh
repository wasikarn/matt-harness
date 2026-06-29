#!/usr/bin/env bash
# 24. Agent tool-grant tokens — each token in tools: must be a real Claude Code
# tool. code.claude.com/docs/en/tools-reference. Strips a (specifier) suffix
# before checking, so 'Bash(git:*)' validates as 'Bash'. Catches typos that
# silently drop a grant (e.g. 'Bsh' grants nothing). Process substitution (not a
# pipe) keeps warn() in the current shell so WARN_COUNT folds into the exit code.
# Also strips JSON-array brackets and quotes (`["Read", "Write"]` is valid YAML
# and is the upstream ECC convention; the audit must accept it, not flag every
# bracket as a typo).
VALID_TOOLS="Agent Bash CronCreate CronDelete CronList Edit EnterWorktree ExitWorktree Glob Grep LSP ListMcpResourcesTool Monitor NotebookEdit PowerShell PushNotification Read ReadMcpResourceTool RemoteTrigger SendMessage ShareOnboardingGuide Skill TaskCreate TaskGet TaskList TaskStop TaskUpdate ToolSearch WebFetch WebSearch Workflow Write"
while IFS= read -r badtok; do
  warn "$badtok"
done < <(
  for f in "$CLAUDE_DIR/agents"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    tv=$(fm_get "$f" "tools" --block)
    [ -n "$tv" ] || continue
    for tok in $(echo "$tv" | tr ',' ' '); do
      # Strip JSON-array brackets and double-quotes so upstream ECC bracket
      # syntax (`["Read", "Write"]`) validates as `Read Write`.
      tok="${tok#[}"; tok="${tok%]}"; tok="${tok%\"}"; tok="${tok#\"}"
      base="${tok%%(*}"
      case " $VALID_TOOLS " in
        *" $base "*) ;;
        *) echo "agent '$name' tools: token '$tok' is not a known Claude Code tool" ;;
      esac
    done
  done
)

