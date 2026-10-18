#!/usr/bin/env bash
# usage: review.sh <name> approve [note]
#        review.sh <name> changes "<what to change>"
# Records the lead agent's review against the task's current commit. Approval
# requires a passing verification of that same commit (or --allow-unverified,
# which should only be used after the user agreed).
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; decision=${2:?approve|changes}; shift 2
allow=0; note=""
for a in "$@"; do case "$a" in --allow-unverified) allow=1;; *) note="$note${note:+ }$a";; esac; done
require_task "$name"
wt=$(task_wt "$name"); sha=$(git -C "$wt" rev-parse HEAD)
pid_alive "$(state_get "$name" pid)" && die "task $name is still running; stop.sh it or wait"
case "$decision" in
  approve)
    worktree_dirty "$wt" && die "worktree has uncommitted changes; nothing approved"
    if [ "$(state_get "$name" verify_sha)" != "$sha" ] || [ "$(state_get "$name" verify_result)" != pass ]; then
      [ $allow = 1 ] || die "commit ${sha:0:12} has no passing verification (run verify.sh, or pass --allow-unverified after the user agreed)"
    fi
    state_set "$name" review approved; state_set "$name" review_sha "$sha"; state_set "$name" review_note "$note"
    state_set "$name" status approved; tlog "$name" "review approved ${sha:0:12} $note" ;;
  changes)
    [ -n "$note" ] || die "say what needs to change"
    feedback_add "$name" "Review feedback from the lead agent: $note"
    state_set "$name" review changes; state_set "$name" review_sha "$sha"
    state_set "$name" status changes-requested; tlog "$name" "review: changes requested — $note"
    echo "queued as feedback; run dispatch.sh $name to continue" ;;
  *) die "decision must be approve or changes" ;;
esac
