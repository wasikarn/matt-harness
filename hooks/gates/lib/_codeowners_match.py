#!/usr/bin/env python3
# Shared CODEOWNERS discovery + matching logic, used by
# commands/ship-merge/COMMAND.md's step 7 (CLI wrapper below, argv/stdout contract
# unchanged from the original embedded block). Its second caller,
# hooks/gates/convergence-merge-gate.sh, was retired 2026-08-24 (#82).
#
# Extracted 2026-08-15 from ship-merge.md's already-fixed matcher (3 bugs
# fixed same day in cdd3cbd: case-fold-independent path matching was never
# the issue here, but the discovery loop's exit-code-vs-content-emptiness
# bug, the COMMENTED-after-APPROVED bug, and the email-owner dead-end all
# were) -- carried over as-is, not re-derived. A mh:plan-reviewer pass on
# the extraction plan (needs-revision, 2 Critical) is why discover() exists
# as a shared function too: the first draft only shared the matcher and left
# the discovery loop as a second, unshared reimplementation -- the exact
# "same logic in 2+ files, no machine-check" pattern this repo has already
# been bitten by (see this file's own git history for the discovery loop's
# one real bug, found and fixed the same day this file was created).
#
# GitHub's documented CODEOWNERS grammar (verified against GitHub's own
# docs, 2026-08-14): two .gitignore features do NOT carry over -- `[ ]`
# character ranges and `!` negation -- so the matcher needs neither. No `/`
# in a pattern matches the basename at any depth; a `/` anywhere except a
# lone trailing one anchors to the repo root; a trailing `/` matches that
# directory and everything under it; `*` matches within one path segment,
# `**` crosses segments, `?` matches one character; last-matching-line wins.

import re


def translate_pattern(pat):
    if "[" in pat or pat.startswith("!"):
        return None
    is_dir = pat.endswith("/")
    p = pat[:-1] if is_dir else pat
    if not p:
        return None
    anchored = "/" in p
    if p.startswith("/"):
        p = p[1:]
    segments = p.split("/") if p else []
    if not segments:
        return None
    globstar_count = sum(1 for s in segments if s == "**")
    if globstar_count > 1:
        return None

    def seg_to_regex(seg):
        part = ""
        for c in seg:
            if c == "*":
                part += "[^/]*"
            elif c == "?":
                part += "[^/]"
            else:
                part += re.escape(c)
        return part

    if globstar_count == 1:
        idx = segments.index("**")
        before, after = segments[:idx], segments[idx + 1:]
        before_re = "/".join(seg_to_regex(s) for s in before)
        after_re = "/".join(seg_to_regex(s) for s in after)
        if before_re and after_re:
            body = before_re + "/(?:.*/)?" + after_re
        elif before_re:
            body = before_re + "(?:/.*)?"
        elif after_re:
            body = "(?:.*/)?" + after_re
        else:
            body = ".*"
    else:
        body = "/".join(seg_to_regex(s) for s in segments)
    body = ("^" + body) if anchored else ("(^|.*/)" + body)
    body += "(/.*)?$" if is_dir else "$"
    try:
        return re.compile(body)
    except re.error:
        return None


def parse_codeowners(text):
    rules = []
    for raw_line in text.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        pattern, owners = parts[0], parts[1:]
        rules.append((pattern, translate_pattern(pattern), owners))
    return rules


def owners_for_file(rules, path):
    result, unsupported = None, False
    for _pattern, regex, owners in rules:
        if regex is None:
            unsupported = True
            continue
        if regex.match(path):
            result = owners
    return result, unsupported


def evaluate(codeowners_text, changed_files, reviews, head_sha):
    """changed_files: list of changed file path strings.
    reviews: list of dicts, each with an "author":{"login":...}, "state",
    and "commit":{"oid":...} -- gh's reviews API generally ties a review to
    the commit it was submitted against, but GitHub's own GraphQL schema
    documents PullRequestReview.commit as nullable (confirmed via
    `gh api graphql` introspection, 2026-08-15 -- e.g. a rewritten-history
    case); a missing/null commit is treated the same as a non-matching one
    below, so this is handled safely either way. head_sha: the PR's current
    headRefOid. A review whose commit oid doesn't match head_sha is stale
    and does not count, even if its state is APPROVED: the owned files may
    have changed again since that review was submitted, and GitHub only
    strips stale reviews itself when branch protection's "dismiss stale
    reviews" setting is enabled repo-side -- an out-of-band precondition
    this function has no way to check, so it enforces the pin itself.
    Returns (verdict, reason, detail_lines). verdict is one of
    "PASS" / "STOP" / "DEFERRED". detail_lines is a list of already-
    formatted "  <owner> needed for: <files>" strings, empty when there's
    nothing to detail -- a user-owner entry gets an extra "(approved an
    earlier commit...)" clause appended when a stale decision-state review
    exists for them, so a rebase-invalidated approval doesn't render
    identically to "never reviewed."
    """
    rules = parse_codeowners(codeowners_text)
    required = {}
    any_unsupported = False
    for f in changed_files:
        f = f.strip()
        if not f:
            continue
        owners, unsupported = owners_for_file(rules, f)
        if unsupported:
            any_unsupported = True
        if owners:
            for o in owners:
                required.setdefault(o, set()).add(f)

    if any_unsupported:
        return "STOP", "unparseable-pattern", []
    if not required:
        return "PASS", "no-owned-files-changed", []

    # Only these three states carry review-decision weight on GitHub; a
    # COMMENTED review left after an APPROVED one does not revoke the
    # approval, so it must not overwrite it here.
    decision_states = ("APPROVED", "CHANGES_REQUESTED", "DISMISSED")
    latest_by_author = {}
    stale_reviewers = set()
    for r in reviews:
        login = (r.get("author") or {}).get("login")
        state = r.get("state")
        commit_oid = (r.get("commit") or {}).get("oid")
        if not login or state not in decision_states:
            continue
        if commit_oid == head_sha:
            latest_by_author[login] = state  # array order == chronological; last write wins
        else:
            stale_reviewers.add(login)
    approved = set(a for a, s in latest_by_author.items() if s == "APPROVED")

    unsatisfied_user, unsatisfied_team = [], []
    for owner, files in required.items():
        if owner.startswith("@"):
            if "/" in owner:
                unsatisfied_team.append((owner, sorted(files)))
            else:
                login = owner.lstrip("@")
                if login not in approved:
                    # A stale review only explains the gap when there's no
                    # current-head decision at all -- a CHANGES_REQUESTED on
                    # head plus an old stale APPROVED should read as "changes
                    # requested," not "stale approval."
                    note = (
                        " (approved an earlier commit -- stale after a"
                        " rebase/new push, needs re-approval on the"
                        " current head)"
                        if login not in latest_by_author and login in stale_reviewers
                        else ""
                    )
                    unsatisfied_user.append((owner, sorted(files), note))
        else:
            # A bare email-address owner (GitHub CODEOWNERS supports these)
            # -- the reviews API only returns GitHub logins, never emails,
            # so this matcher cannot resolve it either way. Same DEFERRED
            # treatment as an @org/team entry, not a permanent STOP.
            unsatisfied_team.append((owner, sorted(files)))

    if unsatisfied_user:
        detail = ["  %s needed for: %s%s" % (o, ", ".join(f), n) for o, f, n in unsatisfied_user]
        return "STOP", "missing-user-approval", detail
    if unsatisfied_team:
        detail = ["  %s needed for: %s" % (o, ", ".join(f)) for o, f in unsatisfied_team]
        return "DEFERRED", "unverified-owner-approval", detail
    return "PASS", "all-required-owners-approved", []


def discover(run_gh, search_paths=(".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS")):
    """run_gh(path) -> (returncode, stdout, stderr), same shape as a
    subprocess.run() result's fields -- injected so this stays testable
    without shelling out to a real `gh`.

    Returns (content, found, error).
    found=True with content="" means an existing-but-EMPTY file (still
    authoritative -- GitHub's own first-found-wins search order stops at
    the first path that exists, content notwithstanding) -- NOT the same
    as absent everywhere. Branches on the actual return code, not on
    whether stdout came back non-empty: an existing-but-empty file at the
    first search path must still short-circuit the search, but must be
    labeled "found, zero rules," not misread as "absent everywhere" the
    way a content-emptiness check would collapse the two.
    error is non-empty only on a genuine non-404 fetch failure (the
    fail-closed signal) -- a 404 at one path just means "try the next
    one," not an error.
    found=False with error="" means every path in search_paths genuinely
    404'd -- verified-absent, not "we don't know."
    """
    for path in search_paths:
        rc, out, err = run_gh(path)
        if rc == 0:
            return out, True, ""
        if "404" not in (err or ""):
            return "", False, (err or "unknown fetch error")
    return "", False, ""


def _real_run_gh(path, head_sha, timeout):
    import subprocess

    r = subprocess.run(
        [
            "gh", "api", "-H", "Accept: application/vnd.github.raw",
            "repos/{owner}/{repo}/contents/%s?ref=%s" % (path, head_sha),
        ],
        capture_output=True, text=True, timeout=timeout,
    )
    return r.returncode, r.stdout, r.stderr


def discover_live(head_sha, timeout=10):
    """discover() wired to a real `gh api` call, timeout in seconds per
    path (Medium #1 from the plan-reviewer pass: worst case 3 paths *
    timeout, only on the rarest path -- a merge attempt past an already-
    clean review -- so a shorter per-call budget than the sibling CI
    check's 20s is deliberate, not an oversight).
    """
    return discover(lambda p: _real_run_gh(p, head_sha, timeout))


if __name__ == "__main__":
    import sys

    if len(sys.argv) >= 3 and sys.argv[1] == "--discover":
        # Bash-consumable CLI mode for ship-merge.md's discovery loop --
        # exit 0 + content on stdout = found (content may be empty, still
        # authoritative per GitHub's first-found-wins search order); exit 3
        # = genuinely absent everywhere (N/A); exit 4 + error on stderr =
        # fetch error, fail closed. Keeps the discovery loop itself as ONE
        # shared implementation (discover() above) instead of a second,
        # independent bash reimplementation -- the exact gap a
        # mh:plan-reviewer pass caught in the first draft of this file.
        head_sha = sys.argv[2]
        content, found, error = discover_live(head_sha)
        if error:
            print(error, file=sys.stderr)
            sys.exit(4)
        if not found:
            sys.exit(3)
        sys.stdout.write(content)
        sys.exit(0)

    import json

    codeowners_text, changed_files_text, reviews_json, head_sha = sys.argv[1:5]
    changed_files = changed_files_text.splitlines()
    reviews = json.loads(reviews_json)
    verdict, reason, detail_lines = evaluate(codeowners_text, changed_files, reviews, head_sha)
    print(verdict)
    print("reason=%s" % reason)
    for line in detail_lines:
        print(line)
