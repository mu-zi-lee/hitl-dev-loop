#!/usr/bin/env bash
# usage: drive.sh <name>
# Runs agent rounds for a task until it is verified, blocked, failed or out of
# budget. Completion is decided here, not by the agent:
#   report.status == done  AND  real changes exist  AND  changes stay in scope
#   AND  (scheduler commit)  AND  verify.sh passes at that commit.
# A failed round keeps in-flight feedback for the next round; consecutive
# failures, verification failures, rounds, wall time and tokens are capped.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; require_task "$name"
dir=$(task_dir "$name"); wt=$(task_wt "$name")
[ -d "$wt" ] || die "worktree missing: $wt"

lock="$dir/lock"
lock_acquire "$lock" || die "task $name is already being driven (pid $(cat "$lock/pid" 2>/dev/null))"
trap 'lock_release "$lock"' EXIT
state_set "$name" pid $$
state_set "$name" status running
[ -n "$(state_get "$name" started_at)" ] || state_set "$name" started_at "$(now)"

finish() { # status [reason] [exit code]
  state_set "$name" status "$1"
  [ -n "${2:-}" ] && state_set "$name" last_error "$2"
  tlog "$name" "status -> $1${2:+: $2}"
  exit "${3:-0}"
}

footer() {
  local commit_rule verify_rule
  if [ "$AGENT_COMMITS" = scheduler ]; then
    commit_rule="Do NOT run git add/commit. Leave your changes in the working tree; the scheduler commits them after its checks."
  else
    commit_rule="Commit your changes before reporting done. No Co-Authored-By or agent sign-off lines."
  fi
  if [ -n "$AGENT_VERIFY_CMD" ]; then
    verify_rule="After you report done, the scheduler runs this verification itself: $AGENT_VERIFY_CMD — failures come back to you as feedback."
  else
    verify_rule="There is no automatic verification command; the lead agent and the user review your report and diff."
  fi
  cat <<EOF

---
## Scheduler protocol
- Your final message is a JSON report (schema enforced). status=done only when the whole task is implemented and you ran the targeted tests; in_progress if you will keep working; blocked if you need a human decision (explain in unfinished).
- List in "tests" only commands you actually ran, with their real result.
- $commit_rule
- $verify_rule
EOF
}

prompt="$dir/prompt.md"
fails=0
git_baseline=$(git_config_snapshot)
while :; do
  rounds=$(state_get "$name" rounds 0)
  [ "$rounds" -lt "$MAX_ROUNDS" ] || finish stopped "reached MAX_ROUNDS=$MAX_ROUNDS" 3
  if [ "$TASK_TIME_BUDGET" -gt 0 ] && [ $(( $(now) - $(state_get "$name" started_at) )) -gt "$TASK_TIME_BUDGET" ]; then
    finish budget-exceeded "wall time over ${TASK_TIME_BUDGET}s" 3
  fi
  if [ "$TOKEN_BUDGET" -gt 0 ] && [ "$(state_get "$name" tokens 0)" -gt "$TOKEN_BUDGET" ]; then
    finish budget-exceeded "tokens over $TOKEN_BUDGET" 3
  fi

  feedback_take "$name" || true
  inflight=$(feedback_inflight "$name")
  if [ -z "$(state_get "$name" session)" ]; then
    mode=start
    { cat "$AGENT_HOME/briefs/common.md" "$AGENT_HOME/briefs/$name.md"
      if [ -s "$inflight" ]; then printf '\n## Additional feedback from the user\n'; cat "$inflight"; fi
      footer; } > "$prompt"
  else
    mode=resume
    { if [ -s "$inflight" ]; then
        printf 'New feedback. Handle it first, then continue the task:\n'; cat "$inflight"
      else
        printf 'Continue the task. Do not stop at a progress update: finish the work, run the targeted tests, then report.\n'
      fi
      footer; } > "$prompt"
  fi

  state_inc "$name" rounds
  tlog "$name" "round $((rounds + 1)) ($mode)"
  agent_run "$name" "$mode" "$prompt"; arc=$?
  if ! git_config_restore "$git_baseline"; then
    tlog "$name" "repaired shared git config changed during the round (core.worktree/core.bare)"
    feedback_add "$name" "Do not modify the repository's git configuration (.git/config, core.worktree, core.bare). It was changed during your last round and has been restored. Work only inside your worktree."
  fi
  if [ $arc = 0 ]; then
    fails=0
    feedback_ack "$name"
  else
    fails=$((fails + 1))
    tlog "$name" "agent error ($fails/$MAX_FAILS): $(state_get "$name" last_error)"
    [ "$fails" -lt "$MAX_FAILS" ] || finish failed "$(state_get "$name" last_error)" 2
    continue
  fi

  report="$dir/report.json"
  rstatus=$(json_get "$report" status 2>/dev/null || echo unknown)
  summary=$(json_get "$report" summary 2>/dev/null || echo "")
  state_set "$name" report_status "$rstatus"
  tlog "$name" "report: $rstatus — $summary"

  case "$rstatus" in
    blocked)
      finish blocked "agent needs a decision: $summary" 0 ;;
    done)
      if ! has_changes "$name"; then
        feedback_add "$name" "You reported status=done, but the worktree has no changes relative to the task base. Implement the task, or report blocked and explain why nothing needs to change."
        continue
      fi
      oos=$(out_of_scope "$name")
      if [ -n "$oos" ]; then
        state_inc "$name" verify_fails
        feedback_add "$name" "These files are outside this task's allowed scope; revert them, or report blocked and explain why they are required:
$oos"
        [ "$(state_get "$name" verify_fails 0)" -lt "$MAX_VERIFY_FAILS" ] || finish verify-failed "out-of-scope changes: $(echo "$oos" | tr '\n' ' ')" 1
        continue
      fi
      if worktree_dirty "$wt"; then
        if [ "$AGENT_COMMITS" = scheduler ]; then
          git -C "$wt" add -A && git -C "$wt" commit -q -m "${summary:-$name}" -m "Task: $name" \
            || finish failed "scheduler commit failed" 2
          tlog "$name" "committed $(git -C "$wt" rev-parse --short HEAD)"
        else
          feedback_add "$name" "You reported done but left uncommitted changes. Commit them, then report again."
          continue
        fi
      fi
      "$HERE/verify.sh" "$name"; vrc=$?
      case $vrc in
        0) finish verified "" 0 ;;
        2) finish needs-review "no AGENT_VERIFY_CMD configured; review the diff before integrating" 0 ;;
        *) state_inc "$name" verify_fails
           feedback_add "$name" "Scheduler verification failed at $(git -C "$wt" rev-parse --short HEAD) (\`$AGENT_VERIFY_CMD\`). Fix the cause. Tail of the log:
\`\`\`
$(tail -40 "$dir/verify.log")
\`\`\`"
           [ "$(state_get "$name" verify_fails 0)" -lt "$MAX_VERIFY_FAILS" ] || finish verify-failed "verification failed $MAX_VERIFY_FAILS times" 1
           ;;
      esac
      ;;
    *) : ;;  # in_progress or unparsable report: the next round resumes
  esac
done
