#!/usr/bin/env bash
# Records, locally, the outcome of an independent review of the current
# commit. Run by the reviewer, never by the author, after reviewing HEAD.
#
#   tool/record-review.sh <reviewer> <no-blocking-findings|changes-required|verification-incomplete>
#
# The record lives in .git (it is never pushed) and is bound to the exact
# commit hash: amending or rebasing requires a new review. It prevents
# accidental publication; it cannot prove independence against someone
# willing to forge it, so the review itself is also summarized in the PR.
set -euo pipefail

reviewer="${1:?reviewer name required}"
outcome="${2:?outcome required}"
case "$outcome" in
  no-blocking-findings|changes-required|verification-incomplete) ;;
  *) echo "unknown outcome: $outcome" >&2; exit 2 ;;
esac

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "record-review: uncommitted changes; review a committed state." >&2
  exit 1
fi

head="$(git rev-parse HEAD)"
author_trailers="$(git log -1 --format='%an%n%(trailers:key=Co-Authored-By,valueonly)' "$head")"
reviewer_word="$(printf '%s' "$reviewer" | awk '{print tolower($1)}')"
if printf '%s' "$author_trailers" | tr '[:upper:]' '[:lower:]' | grep -qw -- "$reviewer_word"; then
  echo "record-review: '$reviewer' appears as an author of $head; an author cannot review its own change." >&2
  exit 1
fi

# Stored in the common git directory, shared by every linked worktree.
dir="$(git rev-parse --path-format=absolute --git-common-dir)/fluvie-reviews"
mkdir -p "$dir"
{
  echo "commit: $head"
  echo "reviewer: $reviewer"
  echo "outcome: $outcome"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$dir/$head"
echo "Recorded: $reviewer -> $outcome for $head"
