#!/usr/bin/env bash
# usage: new-task.sh <name> [base-ref]  — worktree + branch + brief stub
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; base=${2:-$INTEGRATION_BRANCH}
case "$name" in *[!a-z0-9-]*) echo "use lowercase letters, digits and dashes" >&2; exit 1;; esac
mkdir -p "$WT_ROOT"
git -C "$REPO_ROOT" worktree add -q -b "$TASK_BRANCH_PREFIX$name" "$(task_dir "$name")" "$base"
brief="$AGENT_HOME/briefs/$name.md"
[ -f "$brief" ] || sed "s/{{name}}/$name/g" "$HERE/../templates/task-brief.md" > "$brief"
echo "worktree: $(task_dir "$name")  branch: $TASK_BRANCH_PREFIX$name"
echo "brief:    $brief  (fill it in, then: dispatch.sh $name)"
