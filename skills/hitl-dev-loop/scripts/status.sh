#!/usr/bin/env bash
# usage: status.sh — one line per task: commits, uncommitted files, done, pending feedback, running.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
printf '%-22s %-8s %-10s %-6s %-9s %-8s %s\n' TASK COMMITS UNCOMMITTED DONE FEEDBACK RUNNING LAST-LOG
for brief in "$AGENT_HOME"/briefs/*.md; do
  name=$(basename "$brief" .md); [ "$name" = common ] && continue
  wt=$(task_dir "$name"); [ -d "$wt" ] || continue
  base=$(git -C "$wt" merge-base HEAD "$INTEGRATION_BRANCH" 2>/dev/null)
  commits=$(git -C "$wt" rev-list --count "$base"..HEAD 2>/dev/null || echo ?)
  dirty=$(git -C "$wt" diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')
  done_=no; grep -Eq "$DONE_MARKER" "$(task_final "$name")" 2>/dev/null && done_=yes
  fb=no; [ -f "$AGENT_HOME/feedback/$name.md" ] && fb=pending
  run=no; pgrep -f "$wt" >/dev/null 2>&1 && run=yes
  last=$(date -r "$(task_log "$name")" +%H:%M 2>/dev/null || echo -)
  printf '%-22s %-8s %-10s %-6s %-9s %-8s %s\n' "$name" "$commits" "$dirty" "$done_" "$fb" "$run" "$last"
done
