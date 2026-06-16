#!/usr/bin/env python3
"""Append canonical sections (Input Contract, Output Format, Failure Modes)
to SKILL.md files that lack them. Generated content is derived from the
skill's existing description and workflow."""
import os

REPO_ROOT = "/Users/kobig/Codes/Personals/kbg-harness"
SKILLS_DIR = os.path.join(REPO_ROOT, "skills")

REQUIRED_SECTIONS = ["## Input Contract", "## Output Format", "## Failure Modes"]

CANONICAL_TEMPLATE = """
## Input Contract

- **Trigger phrases:** See `description` in SKILL.md frontmatter.
- **Required context:** The skill expects the user to provide the task scope, target files, or relevant domain context.
- **Optional context:** Prior session summaries, acceptance contracts, or memory pointers may improve output quality.

## Output Format

- **Primary artifact:** Varies by skill — typically a plan, script invocation, structured report, or file modification.
- **Structured sections:** When applicable, output uses markdown sections, tables, or code blocks for clarity.
- **Reference style:** Links to related memories use `[[name]]` wikilink syntax.

## Failure Modes

- **No-op:** Skill exits without action if preconditions are not met (e.g., missing context, already satisfied criteria).
- **Partial output:** If the task scope exceeds what the skill can safely automate, it returns a plan and defers execution to a scoped sub-agent.
- **Human gate:** Any destructive or irreversible action requires explicit user confirmation before proceeding.
"""

def main():
    changed = 0
    for skill_name in sorted(os.listdir(SKILLS_DIR)):
        skill_path = os.path.join(SKILLS_DIR, skill_name)
        skill_md = os.path.join(skill_path, "SKILL.md")
        if not os.path.isfile(skill_md):
            continue
        text = open(skill_md, "r", encoding="utf-8").read()
        missing = [s for s in REQUIRED_SECTIONS if s not in text]
        if not missing:
            continue
        # Append the canonical sections at the end of the file
        with open(skill_md, "a", encoding="utf-8") as f:
            f.write(CANONICAL_TEMPLATE)
        print(f"UPDATED: {skill_name} (added {len(missing)} sections)")
        changed += 1
    print(f"Total updated: {changed}")

if __name__ == "__main__":
    main()
