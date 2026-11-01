#!/bin/sh
# Runs the repo's CI (swift test, xtool build, Simulator self-test) on the current commit and
# waits for the result. Used as the build check for Pass 1 phases, because the Mac has no Xcode.
set -eu
branch=$(git branch --show-current)
sha=$(git rev-parse HEAD)
git push -q -u origin "$branch"
# Reuse the run a pull request push already started; dispatch one only when none appears,
# so each commit builds once on the macOS runner.
find_run() {
  gh run list --workflow ios-build.yml --branch "$branch" \
    --json databaseId,headSha --jq ".[] | select(.headSha == \"$sha\") | .databaseId" | head -n 1
}
run=""
for _ in $(seq 1 6); do
  run=$(find_run)
  [ -n "$run" ] && break
  sleep 10
done
if [ -z "$run" ]; then
  gh workflow run ios-build.yml --ref "$branch"
  for _ in $(seq 1 30); do
    run=$(find_run)
    [ -n "$run" ] && break
    sleep 10
  done
fi
[ -n "$run" ] || { echo "ci_check: no CI run started for $sha" >&2; exit 1; }
gh run watch "$run" --exit-status
