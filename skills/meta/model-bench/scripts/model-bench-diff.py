#!/usr/bin/env python3
"""Diff two claude plugin eval aggregate-result.json files and print a labeled comparison.

Schema notes (verified empirically against every real result file on this machine, not from any
claude plugin eval documentation): aggregates.overallScore, aggregates.overallPassRate, top-level
costUsd, cases[].name, cases[].aggregates.score, cases[].aggregates.passRate are always present.
suite.judgeModel, suite.caseFilter, aggregates.meanDelta, and the *Without/delta ablation fields
are present only on a subset of files at the same schemaVersion, so they're read with a default
rather than assumed present.
"""
import argparse
import json
import sys

DEFAULT_JUDGE_MODEL_DISPLAY = "haiku (default)"
DEFAULT_CASE_FILTER_DISPLAY = "all cases"


def load(path):
    with open(path) as f:
        return json.load(f)


def judge_model_display(suite):
    value = suite.get("judgeModel")
    return value if value else DEFAULT_JUDGE_MODEL_DISPLAY


def case_filter_display(suite):
    value = suite.get("caseFilter")
    return value if value else DEFAULT_CASE_FILTER_DISPLAY


def is_agent_dispatch(case):
    prompt = case.get("promptMarkdown") or ""
    return "subagent_type" in prompt


def hard_fail_reasons(label, data):
    reasons = []
    for plugin in (data.get("suite", {}).get("plugins") or []):
        problem = plugin.get("problem")
        if problem:
            reasons.append(f"{label}: plugin problem: {problem}")
    if data.get("partial"):
        reason = data.get("partialReason", "unknown")
        reasons.append(
            f"{label}: partial run (reason: {reason}) — score covers a smaller, "
            "non-random case set, not comparable"
        )
    return reasons


def compare(path_a, path_b, label_a, label_b):
    data_a, data_b = load(path_a), load(path_b)
    suite_a, suite_b = data_a.get("suite", {}), data_b.get("suite", {})

    reasons = hard_fail_reasons(label_a, data_a) + hard_fail_reasons(label_b, data_b)
    if reasons:
        print(f"=== model-bench: {label_a} vs {label_b} ===")
        print("HARD-FAIL: results are not comparable.")
        for r in reasons:
            print(f"  - {r}")
        return 1

    lines = [f"=== model-bench: {label_a} vs {label_b} ==="]
    for label, data in ((label_a, data_a), (label_b, data_b)):
        agg = data.get("aggregates", {})
        lines.append(
            f"{label}: cost=${data.get('costUsd', 0.0):.4f}  "
            f"score={agg.get('overallScore', 0.0):.3f}  "
            f"passRate={agg.get('overallPassRate', 0.0):.3f}"
        )

    warnings = []
    if judge_model_display(suite_a) != judge_model_display(suite_b):
        warnings.append(
            f"judgeModel differs: {label_a}={judge_model_display(suite_a)} "
            f"vs {label_b}={judge_model_display(suite_b)}"
        )
    if case_filter_display(suite_a) != case_filter_display(suite_b):
        warnings.append(
            f"caseFilter differs: {label_a}={case_filter_display(suite_a)} "
            f"vs {label_b}={case_filter_display(suite_b)}"
        )
    if suite_a.get("ablation") != suite_b.get("ablation"):
        warnings.append(
            f"ablation differs: {label_a}={suite_a.get('ablation')} vs {label_b}={suite_b.get('ablation')}"
        )
    if data_a.get("claudeVersion") != data_b.get("claudeVersion"):
        warnings.append(
            f"claudeVersion differs: {label_a}={data_a.get('claudeVersion')} "
            f"vs {label_b}={data_b.get('claudeVersion')}"
        )
    versions_a = [p.get("version") for p in (suite_a.get("plugins") or [])]
    versions_b = [p.get("version") for p in (suite_b.get("plugins") or [])]
    if versions_a != versions_b:
        warnings.append(f"plugin version differs: {label_a}={versions_a} vs {label_b}={versions_b}")

    if warnings:
        lines.append("WARN: results may not be directly comparable:")
        lines.extend(f"  - {w}" for w in warnings)

    cases_total_a = data_a.get("aggregates", {}).get("casesTotal", 0)
    cases_total_b = data_b.get("aggregates", {}).get("casesTotal", 0)
    if cases_total_a == 0 or cases_total_b == 0:
        empty_side = label_a if cases_total_a == 0 else label_b
        lines.append(f"NOTE: casesTotal is 0 on {empty_side} — no cases ran, skipping per-case table.")
        print("\n".join(lines))
        return 0

    cases_a = {c["name"]: c for c in data_a.get("cases", [])}
    cases_b = {c["name"]: c for c in data_b.get("cases", [])}
    common = sorted(set(cases_a) & set(cases_b))
    only_a = sorted(set(cases_a) - set(cases_b))
    only_b = sorted(set(cases_b) - set(cases_a))

    agent_dispatch_count = 0
    lines.append("")
    lines.append(f"{'case':<42} {label_a + ' score':>14} {label_b + ' score':>14} {'delta':>8}")
    for name in common:
        case_a, case_b = cases_a[name], cases_b[name]
        if is_agent_dispatch(case_a) or is_agent_dispatch(case_b):
            agent_dispatch_count += 1
        score_a = case_a.get("aggregates", {}).get("score", 0.0)
        score_b = case_b.get("aggregates", {}).get("score", 0.0)
        lines.append(f"{name:<42} {score_a:>14.3f} {score_b:>14.3f} {score_b - score_a:>+8.3f}")

    if only_a or only_b:
        lines.append("")
        lines.append("Not comparable (present on only one side — different --tag/--case filters?):")
        lines.extend(f"  - {n}: only in {label_a}" for n in only_a)
        lines.extend(f"  - {n}: only in {label_b}" for n in only_b)

    if agent_dispatch_count:
        lines.append("")
        lines.append(
            f"CAVEAT: {agent_dispatch_count} of {len(common)} compared cases dispatch a subagent, "
            "which runs at its"
        )
        lines.append(
            "agents/*.md frontmatter-pinned model regardless of --model. Whether --model reaches "
            "subagent"
        )
        lines.append("dispatch inside the eval sandbox is unverified. Treat these deltas with caution.")

    print("\n".join(lines))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label-a", required=True, help="Label for the first result (e.g. a model name)")
    parser.add_argument("--label-b", required=True, help="Label for the second result")
    parser.add_argument("result_a", help="Path to the first aggregate-result.json")
    parser.add_argument("result_b", help="Path to the second aggregate-result.json")
    args = parser.parse_args()
    sys.exit(compare(args.result_a, args.result_b, args.label_a, args.label_b))


if __name__ == "__main__":
    main()
