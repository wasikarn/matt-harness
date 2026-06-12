#!/usr/bin/env python3
"""Generate minimal evals.json files for skills that lack them.
Uses the skill's SKILL.md description to build 1-2 basic evals."""
import json, os, re, sys

REPO_ROOT = "/Users/kobig/Codes/Personals/kbg-harness"
SKILLS_DIR = os.path.join(REPO_ROOT, "skills")

SKILL_PROMPTS = {
    "7-agent-pattern": [
        {
            "eval_name": "seat-allocation-present",
            "prompt": "Plan a full-stack feature that adds a user dashboard with API endpoints, React components, DB migration, and tests. Use the 7-agent pattern.",
            "expected_output": "A plan that assigns 7 seats in dependency-ordered waves: API/middleware → styles → tests → types → hooks → integration → remaining.",
            "assertions": [
                {"name": "seven_seats_present", "description": "Response lists all 7 canonical seats"},
                {"name": "dependency_order_present", "description": "Response mentions dependency-ordered waves or parallel integration"},
            ]
        },
        {
            "eval_name": "no-re-orchestrate-warning",
            "prompt": "You are Seat 3 (Tests) in a 7-agent pattern build. The parent agent says 'implement unit tests for the new auth middleware'. What do you do?",
            "expected_output": "Returns scoped test artifacts without re-orchestrating the other seats.",
            "assertions": [
                {"name": "scoped_output", "description": "Response focuses only on test artifacts"},
                {"name": "no_parent-re-orchestrate", "description": "Response does not re-plan other seats"},
            ]
        },
    ],
    "accept-task": [
        {
            "eval_name": "contract-locked-before-execution",
            "prompt": "Start a task to refactor the billing module. Lock acceptance.",
            "expected_output": "Creates .scratch/<slug>/ACCEPTANCE.md with locked criteria, start-SHA, and timestamp before any execution.",
            "assertions": [
                {"name": "acceptance_md_present", "description": "Response mentions ACCEPTANCE.md"},
                {"name": "locked_criteria_present", "description": "Response includes success criteria or done-when conditions"},
            ]
        },
    ],
    "article-mine": [
        {
            "eval_name": "verdict-block-present",
            "prompt": "Mine this article: https://example.com/some-article. Summarize its claims.",
            "expected_output": "Returns a structured summary with a verdict block (VERDICT: SKIP / MINE / HALT) and handles auth walls.",
            "assertions": [
                {"name": "verdict_block_present", "description": "Response contains VERDICT: line"},
                {"name": "auth-wall-handled", "description": "Response notes auth-wall or paywall detection"},
            ]
        },
    ],
    "memory-trim": [
        {
            "eval_name": "dry-run-first",
            "prompt": "Trim my memory. MEMORY.md is getting too long.",
            "expected_output": "Runs memory-trim.sh in plan (dry-run) mode first, then waits for human confirmation before apply.",
            "assertions": [
                {"name": "dry_run_mentioned", "description": "Response mentions plan or dry-run mode"},
                {"name": "a3_rubric_present", "description": "Response references the A3 rubric (<2KB delta, <30 min, reversible)"},
            ]
        },
    ],
    "progressive-refine": [
        {
            "eval_name": "pipeline-structure-present",
            "prompt": "Apply progressive refinement to improve the onboarding flow UX.",
            "expected_output": "A pipeline with positive triggers (what to do when signal X appears) and negative triggers (what to stop when signal Y disappears).",
            "assertions": [
                {"name": "positive_trigger_present", "description": "Response includes a positive trigger or 'when' condition"},
                {"name": "negative_trigger_present", "description": "Response includes a negative trigger or 'stop when' condition"},
                {"name": "pipeline_structure", "description": "Response describes a pipeline or staged refinement"},
            ]
        },
    ],
    "recursive-improve": [
        {
            "eval_name": "human-gate-present",
            "prompt": "Set up recursive improvement for the auth module.",
            "expected_output": "Defines clean signals (tests pass, types check, no new lint), a human gate (manual review before next iteration), and stall/debt gates.",
            "assertions": [
                {"name": "clean_signals_present", "description": "Response mentions clean signals (tests/types/lint)"},
                {"name": "human_gate_present", "description": "Response includes a human approval gate"},
                {"name": "stall_gate_present", "description": "Response mentions stall or debt gate"},
            ]
        },
    ],
    "task-sizing": [
        {
            "eval_name": "well-formed-plan",
            "prompt": "Size a task to add OAuth2 login to the app.",
            "expected_output": "A plan with 3-7 concrete steps, each <30 min, with done-when criteria. Not oversized (vague 'implement auth') and not undersized (1-step crumbs).",
            "assertions": [
                {"name": "step_count_reasonable", "description": "Response lists 3-7 concrete steps"},
                {"name": "done_when_present", "description": "Response includes done-when or acceptance criteria per step"},
                {"name": "not_vague", "description": "Steps are specific, not 'implement auth' style vague"},
            ]
        },
    ],
    "triage": [
        {
            "eval_name": "priority-labels-correct",
            "prompt": "Triage these issues: (1) production database is down, (2) add dark mode toggle, (3) refactor internal naming.",
            "expected_output": "P0 for production outage, P1 for feature request, P2 for refactor. With rationale tracing to impact and urgency.",
            "assertions": [
                {"name": "p0_production", "description": "Production outage labeled P0"},
                {"name": "rationale_present", "description": "Each priority includes impact/urgency rationale"},
            ]
        },
    ],
    "types-first": [
        {
            "eval_name": "plan-structure-present",
            "prompt": "Plan a types-first refactor for the user service.",
            "expected_output": "Plan starts with type/interface definitions, then spawn prompts for each agent, and rejects anti-patterns like 'just fix it in the big file'.",
            "assertions": [
                {"name": "types_first_present", "description": "Response starts with type or interface definitions"},
                {"name": "spawn_prompts_present", "description": "Response includes agent spawn prompts"},
                {"name": "anti_pattern_rejected", "description": "Response rejects 'fix it in one big file' anti-pattern"},
            ]
        },
    ],
    "usage-monitor": [
        {
            "eval_name": "opt-in-respected",
            "prompt": "Show me the usage monitor status.",
            "expected_output": "Checks KBG_USAGE_MONITOR env var, respects opt-in, and shows capture status or help.",
            "assertions": [
                {"name": "opt_in_mentioned", "description": "Response mentions KBG_USAGE_MONITOR opt-in"},
                {"name": "help_or_status", "description": "Response shows help, status, or capture mode"},
            ]
        },
    ],
}

TEMPLATE = {
    "skill_name": None,
    "last_reviewed_reason": "generated in 2026-06-12 P2 closure sweep; deferred to quarterly cadence in docs/harness-decay-cadence.md (first sweep 2026-09)",
    "evals": []
}

def main():
    changed = 0
    for skill_name in sorted(os.listdir(SKILLS_DIR)):
        skill_path = os.path.join(SKILLS_DIR, skill_name)
        evals_json_path = os.path.join(skill_path, "evals", "evals.json")
        if not os.path.isdir(skill_path) or skill_name.startswith("_"):
            continue
        if os.path.exists(evals_json_path):
            continue
        if skill_name not in SKILL_PROMPTS:
            print(f"SKIP (no template): {skill_name}")
            continue
        os.makedirs(os.path.dirname(evals_json_path), exist_ok=True)
        data = dict(TEMPLATE)
        data["skill_name"] = skill_name
        data["evals"] = []
        for idx, ev in enumerate(SKILL_PROMPTS[skill_name]):
            data["evals"].append({"id": idx, **ev})
        with open(evals_json_path, "w") as f:
            json.dump(data, f, indent=2)
        print(f"CREATED: {evals_json_path}")
        changed += 1
    print(f"Total created: {changed}")

if __name__ == "__main__":
    main()
