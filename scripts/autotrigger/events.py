"""Event-parsing helpers for measure-autotrigger.

Covers: parse_ts, content_to_text, is_genuine_user_prompt, slash_names,
nudge_target, skill_invocations, assistant_mentions, normalize, _has_dmi,
load_custom_names, iter_project_dirs, segment_turns, expansion_slash_skill.
"""

import glob
import re
import sys
from datetime import datetime
from pathlib import Path

PROJECTS_ROOT = Path.home() / ".claude" / "projects"
CMD_NAME_RE = re.compile(r"<command-name>\s*/?([\w:-]+)\s*</command-name>")
# Nudge content names its target as '/foo' (command) or 'foo' (skill).
NUDGE_TARGET_RE = re.compile(
    r"\[skill-nudge\] Heuristic match:.*?'/?([\w:-]+)'\s+(command|skill)", re.DOTALL
)


def parse_ts(event: dict):
    """Return a timezone-aware datetime from an event's timestamp, or None."""
    ts = event.get("timestamp")
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def content_to_text(content) -> str:
    """Flatten a message.content (str or list of blocks) to searchable text."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for c in content:
            if isinstance(c, dict):
                if c.get("type") == "text":
                    parts.append(c.get("text", ""))
                elif isinstance(c.get("content"), str):
                    parts.append(c["content"])
        return "\n".join(parts)
    return ""


def is_genuine_user_prompt(event: dict) -> bool:
    """True if this is a real user turn (typed prompt or slash), not a tool result."""
    if event.get("type") != "user":
        return False
    if event.get("toolUseResult") is not None:
        return False
    msg = event.get("message")
    if not isinstance(msg, dict):
        return False
    content = msg.get("content")
    if isinstance(content, list):
        # a tool_result echo is a user event but not a prompt
        if any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
            return False
    return True


def slash_names(event: dict) -> set:
    """Slash command names the user typed in this prompt (normalized, no slash)."""
    text = content_to_text(event.get("message", {}).get("content"))
    return {m.lower() for m in CMD_NAME_RE.findall(text)}


def nudge_target(event: dict):
    """If event is a skill-nudge injection, return (target_name, kind) else None."""
    att = event.get("attachment")
    if not isinstance(att, dict):
        return None
    if att.get("hookName") != "UserPromptSubmit":
        return None
    content = att.get("content", "")
    if "[skill-nudge] Heuristic match" not in content:
        return None
    m = NUDGE_TARGET_RE.search(content)
    if not m:
        return None
    return (m.group(1).lower(), m.group(2))  # (name, "command"|"skill")


def skill_invocations(event: dict):
    """Yield (skill_name, caller_type_or_None) for Skill tool_use blocks."""
    if event.get("type") != "assistant":
        return
    for c in event.get("message", {}).get("content", []) or []:
        if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") == "Skill":
            name = (c.get("input", {}) or {}).get("skill", "?")
            caller = c.get("caller")
            ctype = caller.get("type") if isinstance(caller, dict) else None
            yield (name.lower(), ctype)


def assistant_mentions(event: dict, target: str) -> bool:
    """True if assistant text/thinking in this event mentions /target or target."""
    if event.get("type") != "assistant":
        return False
    blob_parts = []
    for c in event.get("message", {}).get("content", []) or []:
        if isinstance(c, dict) and c.get("type") in ("text", "thinking"):
            blob_parts.append(c.get("text", "") or c.get("thinking", ""))
    blob = "\n".join(blob_parts).lower()
    return f"/{target}" in blob or target in blob


def normalize(name: str) -> str:
    """Strip plugin prefix and slash; lowercase. 'skill-creator:skill-creator'->'skill-creator'."""
    name = name.lstrip("/").lower()
    if ":" in name:
        name = name.split(":")[-1]
    return name


def _has_dmi(path: Path) -> bool:
    """True if frontmatter sets disable-model-invocation: true."""
    try:
        txt = path.read_text()
    except OSError:
        return False
    m = re.search(r"^---\n(.*?)\n---", txt, re.DOTALL)
    fm = m.group(1) if m else ""
    return bool(re.search(r"disable-model-invocation:\s*true", fm))


def load_custom_names(repo_root: Path, use_plugin_cache_fallback: bool = False):
    """Custom skills and commands from the repo, with disable-model-invocation flags.

    Excludes scaffolds (leading underscore). Returns:
      skills:   {name: dmi_bool}  — user-authored skills
      commands: {name: dmi_bool}  — user-authored commands (all dmi=True in practice)
    Skills with dmi=True (assert-presence, decommission) and every command can only
    be invoked manually, so they are excluded from the auto-rate denominator.

    Plugin-cache fallback (opt-in via use_plugin_cache_fallback=True): the kbg
    plugin's cache lives at ~/.claude/plugins/cache/kobig/kbg/<version>/. If
    --repo-root is the kbg-harness repo (no claude/skills/ inside it, since the
    symlink-farm delivery model was retired 2026-06-11), walk the cache for the
    latest version. Avoids the /tmp symlink workaround.
    """
    skills, commands = {}, {}
    sdir = repo_root / "claude" / "skills"
    cdir = repo_root / "claude" / "commands"
    used_fallback = False

    if (not sdir.is_dir() or not cdir.is_dir()) and use_plugin_cache_fallback:
        cache_dir = Path.home() / ".claude" / "plugins" / "cache" / "kobig" / "kbg"
        if cache_dir.is_dir():
            versions = sorted(
                [d for d in cache_dir.iterdir()
                 if d.is_dir() and re.match(r"^\d+\.\d+\.\d+", d.name)],
                key=lambda d: tuple(int(x) for x in d.name.split(".")[:3]),
            )
            if versions:
                latest = versions[-1]
                sdir = latest / "skills"
                cdir = latest / "commands"
                used_fallback = True

    if sdir.is_dir():
        for d in sdir.iterdir():
            if d.is_dir() and not d.name.startswith("_") and (d / "SKILL.md").exists():
                skills[d.name.lower()] = _has_dmi(d / "SKILL.md")
    if cdir.is_dir():
        for f in cdir.glob("*.md"):
            if not f.name.startswith("_"):
                commands[f.stem.lower()] = _has_dmi(f)

    if used_fallback and (skills or commands):
        print(f"# Loaded {len(skills)} skills + {len(commands)} commands from plugin cache fallback ({sdir.parent.name})", file=sys.stderr)
    return skills, commands


def iter_project_dirs(scope: str, projects: list):
    if projects:
        for p in projects:
            yield from glob.glob(str(PROJECTS_ROOT / p))
        return
    if scope == "all":
        yield from (str(d) for d in PROJECTS_ROOT.iterdir() if d.is_dir())
    elif scope == "kobig":
        # Named project dirs only. The trailing '-' deliberately excludes the
        # bare '-Users-kobig' home-default project (~2661 throwaway/misc
        # sessions). Verified 2026-05-30: that dir contributes ZERO custom-skill
        # invocations post-nudge, so kobig == all for the rate while scanning
        # ~10x fewer files. Use --scope all to re-confirm that holds.
        yield from (str(d) for d in PROJECTS_ROOT.glob("-Users-kobig-*") if d.is_dir())
    else:  # dotfiles
        yield str(PROJECTS_ROOT / "-Users-kobig-Codes-Personals-dotfiles")


def segment_turns(events: list):
    """Split an ordered event list into turns. Each turn = list of events starting
    at a genuine user prompt. Events before the first prompt are dropped."""
    turns, cur = [], None
    for ev in events:
        if is_genuine_user_prompt(ev):
            if cur is not None:
                turns.append(cur)
            cur = [ev]
        elif cur is not None:
            cur.append(ev)
    if cur is not None:
        turns.append(cur)
    return turns


def expansion_slash_skill(turn_start: dict, by_uuid: dict):
    """If this turn began as a command EXPANSION, return the normalized slash name.

    Typing `/X` emits two user events: a <command-name>/X marker (the MANUAL
    signal, its own n=1 turn) and the command's expanded body, whose parentUuid
    points back at the marker. The body looks like a fresh natural-language prompt,
    so a Skill tool_use that EXECUTES the command lands here and would be misread
    as AUTO — double-counting the one /X action as both manual and auto.
    Verified 2026-05-30 on /ship-merge and /acli (parentUuid == marker uuid).
    Returns the slash skill so the caller can suppress that auto count.
    """
    parent = by_uuid.get(turn_start.get("parentUuid"))
    if parent is None:
        return None
    names = slash_names(parent)
    return normalize(next(iter(names))) if names else None
