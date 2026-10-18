#!/usr/bin/env bash
# usage: new-task.sh <name> [--base REF] [--network] [--scope 'glob'...]
# Creates worktree ../<repo>-wt/<name> on branch codex/<name>, task state and a brief stub.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; shift
valid_name "$name" || die "use lowercase letters, digits and dashes"
base=$INTEGRATION_BRANCH; network=$DEFAULT_NETWORK; scopes=()
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base=$2; shift 2;;
    --network) network=1; shift;;
    --scope) scopes+=("$2"); shift 2;;
    *) die "unknown option $1";;
  esac
done
[ -d "$AGENT_HOME/tasks" ] || die "run init.sh first"
[ -e "$(task_dir "$name")" ] && die "task $name already exists"
git -C "$REPO_ROOT" rev-parse --verify -q "$base^{commit}" >/dev/null || die "unknown base $base"
mkdir -p "$WT_ROOT"
git -C "$REPO_ROOT" worktree add -q -b "$TASK_BRANCH_PREFIX$name" "$(task_wt "$name")" "$base" || die "worktree add failed"
mkdir -p "$(task_dir "$name")"
: > "$(task_dir "$name")/state"
state_set "$name" name "$name"
state_set "$name" branch "$TASK_BRANCH_PREFIX$name"
state_set "$name" base "$(git -C "$(task_wt "$name")" rev-parse HEAD)"
state_set "$name" network "$network"
state_set "$name" status created
state_set "$name" created_at "$(now)"
brief="$AGENT_HOME/briefs/$name.md"
[ -f "$brief" ] || sed "s/{{name}}/$name/g" "$HITL_SKILL_DIR/templates/task-brief.md" > "$brief"
if [ ${#scopes[@]} -gt 0 ]; then printf '%s\n' "${scopes[@]}" > "$AGENT_HOME/briefs/$name.scope"; fi
tlog "$name" "created from $base (network=$network)"
echo "task:     $name  ($TASK_BRANCH_PREFIX$name, network=$network)"
echo "worktree: $(task_wt "$name")"
echo "brief:    $brief"
if [ ${#scopes[@]} -gt 0 ]; then echo "scope:    $AGENT_HOME/briefs/$name.scope"; fi
echo "next:     fill in the brief, then dispatch.sh $name"
