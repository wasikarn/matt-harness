"""Command-detection helpers extracted from run-acceptance.py so the gnarly
regex/command-extraction logic is independently testable. Pure functions
over criterion dicts; no runner/exit-code semantics (those stay in run-acceptance.py).
"""
import re
from typing import Any


KNOWN_CMD_VERBS = {
    "bash", "sh", "npm", "node", "python", "python3", "pytest", "cargo", "go",
    "make", "git", "claude", "gh", "docker", "docker-compose", "kubectl",
    "curl", "wget", "jq", "cat", "grep", "find", "ls", "cd", "mkdir", "rm",
    "cp", "mv", "echo", "test", "true", "false", "exit", "source", ".",
    "./", "../",
    # test / lint / build / pkg verbs that frequently name a file as their arg
    # (so they were the ones wrongly rejected by the file-extension guard):
    "ruff", "tsc", "eslint", "prettier", "mypy", "pyright", "black", "isort",
    "vitest", "jest", "mocha", "playwright", "npx", "pnpm", "yarn", "bun",
    "deno", "pip", "pip3", "uv", "tox", "hatch", "poetry", "mvn", "gradle",
    "terraform", "ansible", "dotnet", "rustc", "rspec", "phpunit", "dart",
}


def looks_like_command(text: str) -> bool:
    """Validate whether extracted text is actually a runnable command.

    Rejects file paths, line references, and prose fragments.
    """
    t = text.strip()
    if not t:
        return False

    first_word = t.split(None, 1)[0].lower().rstrip(";|&")
    has_shell_meta = bool(re.search(r"[|&;<>$=`\"']", t))

    # A known command verb at the front makes it a runnable command EVEN IF it
    # names a file with an extension — `pytest tests/test_api.py`, `bash
    # scripts/check.sh`, `ruff check .` are commands, not prose file references.
    # (The prior order rejected any text containing `.ext` first, so these — the
    # MOST COMMON validation-command shapes — were silently skipped and the
    # acceptance gate reported PASS on an unrun/broken suite.)
    if first_word in KNOWN_CMD_VERBS:
        return True

    # No known verb: now apply the prose/file-reference rejections. A bare file
    # or line reference (`agents/code-explorer.md`, `SKILL.md:42`) is NOT a
    # command; only shell metacharacters indicate an actual command line.
    if re.search(r"\.[a-zA-Z]{2,5}\b", t):  # e.g. agents/code-explorer.md
        return False
    if re.search(r":[0-9]+", t):  # e.g. SKILL.md:42
        return False
    if not has_shell_meta:
        return False

    return True


def detect_executable(criterion: dict[str, Any]) -> bool:
    """Determine whether a criterion text contains an executable shell command.

    Conservative: only flags criteria that unambiguously contain a runnable
    command. Prose that merely *mentions* a command (e.g., "Logic: reads
    tool_input.command") is NOT executable.
    """
    text = criterion["raw"]

    # Skip if explicitly marked manual
    if "(manual)" in text.lower():
        return False

    # Skip descriptive prose prefixes
    desc_prefixes = [
        r"^Logic:\s",
        r"^If\s",
        r"^New\s+file\s",
        r"^File\s",
        r"^Section\s",
        r"^Script:\s",
        r"^Command:\s",
        r"^Logic\s+reads\s",
        r"^Registered\s+in\s",
        r"^Manual\s+smoke",
        r"^No\s+new\s+test",
        r"^Cross-reference\s+from\s",
        r"^Optional\s+anti-pattern",
        r"^No\s+behavior\s+change",
        r"^Includes\s+a\s+claim",
        r"^All\s+tests\s+assert",
        r"^Per-fix\s+bash",
        r"^Fresh-context\s+adversarial",
        r"^6/\d+\s+test\s+fixtures",
    ]
    for pat in desc_prefixes:
        if re.search(pat, text, re.IGNORECASE):
            return False

    # Strong signal 1: explicit backtick command — validate it looks runnable
    backticks = re.findall(r"`([^`]{3,})`", text)
    for bt in backticks:
        if looks_like_command(bt):
            return True

    # Strong signal 2: arrow notation "command → exit N" or "command → pass/fail"
    arrow_match = re.search(
        r"([a-zA-Z0-9_\-./\s]+?)\s*(?:→|->)\s*(?:exit\s+\d+|\d+|pass|fail)",
        text,
    )
    if arrow_match and looks_like_command(arrow_match.group(1)):
        return True

    # Strong signal 3: explicit command prefix at start of criterion
    cmd_prefixes = [
        r"^bash\s+",
        r"^sh\s+",
        r"^npm\s+(test|run\s+\w+)",
        r"^node\s+",
        r"^python3?\s+",
        r"^pytest\s",
        r"^cargo\s+(test|check|build)",
        r"^go\s+(test|build|run)",
        r"^make\s",
        r"^git\s+(diff|log|status|test)",
        r"^claude\s",
        r"^gh\s",
    ]
    for pat in cmd_prefixes:
        if re.search(pat, text, re.IGNORECASE):
            return True

    # Medium signal: explicit "exit N" standalone
    if re.search(r"\bexit\s+\d+\b", text):
        return True

    return False


def extract_command(text: str) -> str | None:
    """Extract the best-effort shell command from criterion text.

    Only extracts commands that are unambiguously runnable.
    """
    # 1. Backtick extraction (strongest signal)
    backticks = re.findall(r"`([^`]{3,})`", text)
    if backticks:
        # Use the longest backtick span that looks like a command
        candidates = [bt.strip() for bt in backticks if looks_like_command(bt.strip())]
        if candidates:
            return max(candidates, key=len)

    # 2. Arrow notation: "command → exit 0"
    arrow_match = re.search(
        r"([a-zA-Z0-9_\-./\s]+?)\s*(?:→|->)\s*(?:exit\s+\d+|\d+|pass|fail)",
        text,
    )
    if arrow_match:
        candidate = arrow_match.group(1).strip()
        if looks_like_command(candidate):
            return candidate

    # 3. Explicit command at start of line
    start_cmd = re.match(
        r"^(bash|sh|npm|node|python3?|pytest|cargo|go|make|git|claude|gh)\s+(.{5,})",
        text,
        re.IGNORECASE,
    )
    if start_cmd:
        return f"{start_cmd.group(1)} {start_cmd.group(2)}".strip()

    # 4. "exit N" standalone — map to "true" (just a presence check)
    if re.match(r"^exit\s+\d+\s*$", text.strip()):
        return "true"

    # 5. Sanity: reject bare file paths or isolated words
    # If the text is just "filename.ext" or "word:line" it's a reference, not a command
    if re.match(r"^[\w./-]+\.\w+\s*$", text.strip()):
        return None
    if re.match(r"^[A-Z][a-z]+\s+[a-z]+\s*$", text.strip()):
        return None

    return None
