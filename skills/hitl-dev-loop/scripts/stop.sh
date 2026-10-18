#!/usr/bin/env bash
# usage: stop.sh <name> — stop a running task. Work in the worktree and
# undelivered feedback are kept; dispatch.sh resumes the same session.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; require_task "$name"
pid=$(state_get "$name" pid)
if pid_alive "$pid"; then
  kill_tree "$pid" TERM
  for _ in 1 2 3 4 5 6 7 8 9 10; do pid_alive "$pid" || break; sleep 1; done
  pid_alive "$pid" && kill_tree "$pid" KILL
fi
lock_release "$(task_dir "$name")/lock"
state_set "$name" status stopped; tlog "$name" "stopped by user"
echo "stopped $name (changes kept in $(task_wt "$name"))"
