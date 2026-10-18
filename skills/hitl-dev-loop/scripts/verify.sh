#!/usr/bin/env bash
# usage: verify.sh <name>
# Independent verification by the scheduler: runs $AGENT_VERIFY_CMD in the
# task worktree at its current commit and records the result against that SHA.
# exit 0 = pass, 1 = fail, 2 = skipped (no command configured).
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; require_task "$name"
wt=$(task_wt "$name"); dir=$(task_dir "$name")
sha=$(git -C "$wt" rev-parse HEAD)
state_set "$name" verify_sha "$sha"; state_set "$name" verify_at "$(now)"
if [ -z "$AGENT_VERIFY_CMD" ]; then
  state_set "$name" verify_result skipped; tlog "$name" "verify skipped (no AGENT_VERIFY_CMD)"; exit 2
fi
if worktree_dirty "$wt"; then
  state_set "$name" verify_result fail
  echo "worktree has uncommitted changes; verification must run on a commit" > "$dir/verify.log"
  tlog "$name" "verify fail: dirty worktree"; exit 1
fi
tlog "$name" "verify ${sha:0:12}: $AGENT_VERIFY_CMD"
(cd "$wt" && run_with_timeout "$VERIFY_TIMEOUT" bash -c "$AGENT_VERIFY_CMD") > "$dir/verify.log" 2>&1 < /dev/null
rc=$?
if [ $rc = 0 ]; then state_set "$name" verify_result pass; tlog "$name" "verify pass"; exit 0; fi
[ $rc = 124 ] && echo "verification timed out after ${VERIFY_TIMEOUT}s" >> "$dir/verify.log"
state_set "$name" verify_result fail; tlog "$name" "verify fail (exit $rc)"; exit 1
