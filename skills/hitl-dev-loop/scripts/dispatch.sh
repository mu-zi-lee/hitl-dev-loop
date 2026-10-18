#!/usr/bin/env bash
# usage: dispatch.sh <name>  — start Codex on the task brief, then keep it going.
# Long-running: start it in the background.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; wt=$(task_dir "$name")
[ -d "$wt" ] || { echo "no worktree $wt (run new-task.sh)" >&2; exit 1; }
mkdir -p "$AGENT_HOME/logs"
base=$(git -C "$wt" rev-parse HEAD)
add_dirs=(--add-dir "$(git_common_dir)")
IFS=: read -r -a extra <<<"$CODEX_WRITABLE_DIRS"
for d in ${extra[@]+"${extra[@]}"}; do [ -n "$d" ] && add_dirs+=(--add-dir "${d/#\~/$HOME}"); done
# shellcheck disable=SC2086
cat "$AGENT_HOME/briefs/common.md" "$AGENT_HOME/briefs/$name.md" | "$CODEX_BIN" exec -C "$wt" -s workspace-write \
  -c "sandbox_workspace_write.network_access=$([ "$CODEX_NETWORK" = 1 ] && echo true || echo false)" \
  "${add_dirs[@]}" $CODEX_EXTRA_ARGS -o "$(task_final "$name")" - > "$(task_log "$name")" 2>&1
echo "exit $?" >> "$(task_log "$name")"
sid=$(grep -m1 "session id" "$(task_log "$name")" | awk '{print $3}')
[ -n "$sid" ] || { echo "codex did not start; see $(task_log "$name")" >&2; exit 1; }
echo "$sid" > "$AGENT_HOME/logs/$name.sid"
exec "$HERE/drive.sh" "$name" "$base"
