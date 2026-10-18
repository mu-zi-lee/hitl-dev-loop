#!/usr/bin/env bash
# usage: dispatch.sh <name> [--detach]
# Starts (or continues) a task: checks the brief and the parallel limit, then
# runs drive.sh. Long-running; run it in the background or use --detach.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; require_task "$name"
brief="$AGENT_HOME/briefs/$name.md"
[ -s "$brief" ] || die "brief is empty: $brief"
grep -q '^## Goal' "$brief" && ! sed -n '/^## Goal/,/^## /p' "$brief" | grep -v '^##' | grep -v '^<!--' | grep -q '[^[:space:]]' \
  && die "the Goal section of $brief is empty"
pid_alive "$(state_get "$name" pid)" && die "task $name is already running (pid $(state_get "$name" pid))"
if git config -f "$(git_config_file)" --get core.worktree >/dev/null 2>&1; then
  die "the shared git config sets core.worktree=$(git config -f "$(git_config_file)" --get core.worktree); git commands in $REPO_ROOT act on that directory. Remove it (git config -f $(git_config_file) --unset core.worktree) after checking both trees."
fi
agent_version >/dev/null || die "agent '$AGENT_ADAPTER' is not available (set CODEX_BIN?)"
active=$(running_tasks | wc -l | tr -d ' ')
[ "$active" -lt "$MAX_PARALLEL" ] || die "$active tasks already running (MAX_PARALLEL=$MAX_PARALLEL): $(running_tasks | tr '\n' ' ')"
"$HERE/conflicts.sh" "$name" --quiet || true
if [ "${2:-}" = --detach ]; then
  nohup "$HERE/drive.sh" "$name" > "$(task_dir "$name")/drive.out" 2>&1 < /dev/null &
  echo "dispatched $name (pid $!)"
else
  exec "$HERE/drive.sh" "$name"
fi
