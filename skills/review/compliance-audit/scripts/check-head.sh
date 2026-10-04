#!/usr/bin/env bash
# check-head.sh <audited-sha> <ref>: exit 0 only when <ref> still resolves to
# the head SHA the audit pinned (issue #395). Run before ship/merge; fetch first
# when <ref> is a remote branch. Exit 1 = the ref moved since the audit (re-audit);
# exit 2 = usage error or a SHA/ref that does not resolve to a commit.
set -u
if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "usage: check-head.sh <audited-sha> <ref>" >&2
  exit 2
fi
audited=$(git rev-parse --verify --quiet "$1^{commit}") || { echo "check-head: audited SHA '$1' does not resolve" >&2; exit 2; }
now=$(git rev-parse --verify --quiet "$2^{commit}") || { echo "check-head: ref '$2' does not resolve" >&2; exit 2; }
if [ "$audited" = "$now" ]; then
  echo "check-head: $2 is still the audited head $audited"
  exit 0
fi
echo "check-head: $2 moved since the audit (audited $audited, now $now); re-audit before shipping" >&2
exit 1
