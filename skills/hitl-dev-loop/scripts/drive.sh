#!/usr/bin/env bash
# usage: drive.sh <name> [base-commit]
# Goal-free continuation: resume until the final reply starts with the done
# marker and the branch moved past base. Does not use Codex goals on purpose.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; wt=$(task_dir "$name")
base=${2:-$(git -C "$wt" merge-base HEAD "$INTEGRATION_BRANCH")}
for i in $(seq 1 "$MAX_ROUNDS"); do
  if [ ! -f "$AGENT_HOME/feedback/$name.md" ] && grep -Eq "$DONE_MARKER" "$(task_final "$name")" 2>/dev/null \
     && [ "$(git -C "$wt" rev-parse HEAD)" != "$base" ]; then
    echo "=== done before round $i $(date)" >> "$(task_log "$name")"; exit 0
  fi
  echo "=== drive round $i $(date)" >> "$(task_log "$name")"
  "$HERE/resume.sh" "$name"
done
echo "=== gave up after $MAX_ROUNDS rounds" >> "$(task_log "$name")"; exit 1
