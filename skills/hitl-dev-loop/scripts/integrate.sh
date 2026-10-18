#!/usr/bin/env bash
# usage: integrate.sh <name> [--allow-unverified]
# Merges an approved task into the integration branch, inside a dedicated
# integration worktree, then verifies the merged result. Gates:
#   - review approved for the task's current commit
#   - verification passed for that same commit (unless --allow-unverified,
#     which needs the user's OK)
#   - the merged result passes AGENT_VERIFY_CMD, otherwise the merge is undone.
# exit 0 integrated, 1 gate/verification failure, 2 merge conflict.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; require_task "$name"
allow=0; [ "${2:-}" = --allow-unverified ] && allow=1
wt=$(task_wt "$name"); sha=$(git -C "$wt" rev-parse HEAD)
pid_alive "$(state_get "$name" pid)" && die "task $name is still running"
worktree_dirty "$wt" && die "task worktree has uncommitted changes"
[ "$(state_get "$name" review)" = approved ] && [ "$(state_get "$name" review_sha)" = "$sha" ] \
  || die "no approved review for ${sha:0:12} (review.sh $name approve)"
if [ "$(state_get "$name" verify_result)" != pass ] || [ "$(state_get "$name" verify_sha)" != "$sha" ]; then
  [ $allow = 1 ] || die "${sha:0:12} has no passing verification"
fi

lock="$AGENT_HOME/integration.lock"
lock_acquire "$lock" || die "another integration is in progress"
trap 'lock_release "$lock"' EXIT
if [ ! -d "$INTEGRATION_WT" ]; then
  git -C "$REPO_ROOT" worktree add -q "$INTEGRATION_WT" "$INTEGRATION_BRANCH" || die "cannot create integration worktree"
fi
[ "$(git -C "$INTEGRATION_WT" rev-parse --abbrev-ref HEAD)" = "$INTEGRATION_BRANCH" ] || die "integration worktree is not on $INTEGRATION_BRANCH"
worktree_dirty "$INTEGRATION_WT" && die "integration worktree has uncommitted changes: $INTEGRATION_WT"
before=$(git -C "$INTEGRATION_WT" rev-parse HEAD)
summary=$(json_get "$(task_dir "$name")/report.json" summary 2>/dev/null || echo "$name")
if ! git -C "$INTEGRATION_WT" merge -q --no-ff "$sha" -m "Integrate $name: $summary" >/dev/null 2>&1; then
  files=$(git -C "$INTEGRATION_WT" diff --name-only --diff-filter=U | tr '\n' ' ')
  git -C "$INTEGRATION_WT" merge --abort 2>/dev/null
  state_set "$name" status conflict; state_set "$name" last_error "merge conflict: $files"
  tlog "$name" "integration conflict: $files"
  echo "conflict in: $files"
  echo "resolve by updating the task branch (git -C $wt merge $INTEGRATION_BRANCH), then verify/review again"
  exit 2
fi
merged=$(git -C "$INTEGRATION_WT" rev-parse HEAD)
result=skipped
if [ -n "$AGENT_VERIFY_CMD" ]; then
  if (cd "$INTEGRATION_WT" && run_with_timeout "$VERIFY_TIMEOUT" bash -c "$AGENT_VERIFY_CMD") > "$AGENT_HOME/integration-verify.log" 2>&1 < /dev/null; then
    result=pass
  else
    git -C "$INTEGRATION_WT" reset -q --hard "$before"
    state_set "$name" status integration-failed
    state_set "$name" last_error "merged result failed verification; merge undone (see $AGENT_HOME/integration-verify.log)"
    tlog "$name" "integration verification failed; reset to ${before:0:12}"
    echo "merged result failed verification; integration branch left at ${before:0:12}"; exit 1
  fi
fi
printf 'sha=%s\nverify=%s\nat=%s\ntask=%s\n' "$merged" "$result" "$(now)" "$name" > "$AGENT_HOME/integration.state"
state_set "$name" status integrated; state_set "$name" integrated_sha "$merged"
tlog "$name" "integrated as ${merged:0:12} (verify: $result)"
echo "integrated $name -> $INTEGRATION_BRANCH ${merged:0:12} (verify: $result)"
