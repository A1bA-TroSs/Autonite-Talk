#!/bin/sh
# Runs the repo's CI (swift test, xtool build, Simulator self-test) on the current commit and
# waits for the result. Used as the build check for Pass 1 phases, because the Mac has no Xcode.
set -eu
branch=$(git branch --show-current)
sha=$(git rev-parse HEAD)
git push -q -u origin "$branch"
gh workflow run ios-build.yml --ref "$branch"
run=""
for _ in $(seq 1 30); do
  run=$(gh run list --workflow ios-build.yml --branch "$branch" --event workflow_dispatch \
    --json databaseId,headSha --jq ".[] | select(.headSha == \"$sha\") | .databaseId" | head -n 1)
  [ -n "$run" ] && break
  sleep 10
done
[ -n "$run" ] || { echo "ci_check: no CI run started for $sha" >&2; exit 1; }
gh run watch "$run" --exit-status
