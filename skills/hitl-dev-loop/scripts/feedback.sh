#!/usr/bin/env bash
# usage: feedback.sh <name> "<text>"   (or: ... | feedback.sh <name> -)
# Queues feedback for a task. It is delivered at the start of the next round
# and only marked acknowledged after that round succeeds.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; require_task "$name"
text=${2:?feedback text or -}
[ "$text" = - ] && text=$(cat)
feedback_add "$name" "$text"
tlog "$name" "feedback queued"
if pid_alive "$(state_get "$name" pid)"; then echo "queued; the running driver delivers it next round"
else echo "queued; run dispatch.sh $name to deliver it"; fi
