#!/usr/bin/env bash
# Test suite for the hitl-dev-loop scripts. Uses tests/fake-codex instead of a
# real agent. Usage: tests/run.sh [test-name-substring]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
S=$ROOT/skills/hitl-dev-loop/scripts
FAKE=$ROOT/tests/fake-codex
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export CODEX_BIN=$FAKE
filter=${1:-}
pass=0; fail=0; failed_names=""

# ---- helpers ----------------------------------------------------------------
setup() { # fresh repo + agent home; sets REPO, FAKE_DIR
  WORK=$(mktemp -d); REPO=$WORK/demo; mkdir -p "$REPO"
  export FAKE_DIR=$WORK/fake; mkdir -p "$FAKE_DIR"
  (cd "$REPO" && git init -q && echo base > work.txt && git add work.txt && git commit -q -m init)
  unset AGENT_VERIFY_CMD AGENT_SHIP_CMD MAX_FAILS MAX_ROUNDS ROUND_TIMEOUT MAX_PARALLEL MAX_VERIFY_FAILS 2>/dev/null
  cd "$REPO" && "$S/init.sh" >/dev/null
}
script() { printf '%s\n' "$@" > "$FAKE_DIR/script"; }
brief() { # name: write a non-empty goal
  printf '# Task\n\n## Goal\nDo the %s thing.\n\n## Acceptance criteria\n- done\n' "$1" > "$REPO/.agent-loop/briefs/$1.md"
}
st() { grep -m1 "^$2=" "$REPO/.agent-loop/tasks/$1/state" | cut -d= -f2-; }
check() { # description condition...
  local d=$1; shift
  if "$@"; then return 0; fi
  echo "    FAIL: $d"
}
eq() { [ "$1" = "$2" ] || { echo "    expected '$2', got '$1'"; return 1; }; }
contains() { grep -q -- "$2" "$1" 2>/dev/null || { echo "    '$1' lacks '$2'"; return 1; }; }
run_case() {
  local name=$1
  [ -z "$filter" ] || case "$name" in *"$filter"*) ;; *) return;; esac
  ( setup; "$name" ) > "/tmp/hitl-test-$$.log" 2>&1
  local rc=$?
  if [ $rc = 0 ] && ! grep -q '    FAIL\|    expected\|    lacks' "/tmp/hitl-test-$$.log"; then
    pass=$((pass + 1)); echo "ok   $name"
  else
    fail=$((fail + 1)); failed_names="$failed_names $name"; echo "FAIL $name"; sed 's/^/     | /' "/tmp/hitl-test-$$.log" | tail -25
  fi
  rm -f "/tmp/hitl-test-$$.log"
}

# ---- cases ------------------------------------------------------------------
t_init_is_idempotent() {
  echo "# marker" >> .agent-loop/config.sh
  "$S/init.sh" >/dev/null; "$S/init.sh" >/dev/null
  check "exclude has one entry" eq "$(grep -c '^/.agent-loop/$' "$(git rev-parse --git-common-dir)/info/exclude")" 1
  check "config not overwritten" contains .agent-loop/config.sh "# marker"
  check "integration branch exists" git rev-parse --verify -q refs/heads/codex/integration
}

t_new_task_rejects_duplicates_and_bad_names() {
  "$S/new-task.sh" alpha >/dev/null
  check "duplicate refused" bash -c "! '$S/new-task.sh' alpha 2>/dev/null"
  check "bad name refused" bash -c "! '$S/new-task.sh' 'Bad_Name' 2>/dev/null"
  check "worktree created" test -d "../demo-wt/alpha"
  check "status created" eq "$(st alpha status)" created
  check "network off by default" eq "$(st alpha network)" 0
}

t_dispatch_refuses_empty_goal() {
  "$S/new-task.sh" alpha >/dev/null
  check "empty goal refused" bash -c "! '$S/dispatch.sh' alpha 2>/dev/null"
}

t_start_failure_trips_circuit_breaker() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script fail fail fail
  MAX_FAILS=3 "$S/dispatch.sh" alpha 2>/dev/null
  check "status failed" eq "$(st alpha status)" failed
  check "error recorded" contains .agent-loop/tasks/alpha/state "fake model error"
  check "no session kept from a failed start" eq "$(st alpha session)" ""
  check "stopped after 3 calls" eq "$(cat "$FAKE_DIR/calls")" 3
}

t_feedback_survives_failed_round() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  "$S/feedback.sh" alpha "please use blue" >/dev/null
  script fail done-change
  AGENT_VERIFY_CMD=true "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "failed round got the feedback" contains "$FAKE_DIR/prompt.1" "please use blue"
  check "retry got the feedback again" contains "$FAKE_DIR/prompt.2" "please use blue"
  check "acknowledged after success" bash -c "ls .agent-loop/tasks/alpha/feedback.acked.* >/dev/null 2>&1"
  check "nothing left pending" test ! -s .agent-loop/feedback/alpha.md
  check "verified" eq "$(st alpha status)" verified
}

t_done_without_changes_is_not_done() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script done-nochange done-change
  AGENT_VERIFY_CMD=true "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "second round told about missing changes" contains "$FAKE_DIR/prompt.2" "no changes"
  check "second round resumed the session" eq "$(cat "$FAKE_DIR/mode.2")" resume
  check "verified only after real change" eq "$(st alpha status)" verified
}

t_verification_failure_is_fed_back() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script done-change done-fix
  AGENT_VERIFY_CMD='test -f fixed.txt || { echo "MISSING fixed.txt"; exit 1; }' "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "verify log sent back" contains "$FAKE_DIR/prompt.2" "MISSING fixed.txt"
  check "verified after fix" eq "$(st alpha status)" verified
  check "one verify failure counted" eq "$(st alpha verify_fails)" 1
  check "verify bound to HEAD" eq "$(st alpha verify_sha)" "$(git -C ../demo-wt/alpha rev-parse HEAD)"
  check "scheduler committed (clean tree)" test -z "$(git -C ../demo-wt/alpha status --porcelain)"
}

t_verification_failures_are_capped() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script done-change done-change done-change done-change
  MAX_VERIFY_FAILS=2 AGENT_VERIFY_CMD=false "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "status verify-failed" eq "$(st alpha status)" verify-failed
  check "stopped after 2 rounds" eq "$(cat "$FAKE_DIR/calls")" 2
}

t_out_of_scope_changes_are_rejected() {
  "$S/new-task.sh" alpha --scope 'work.txt' >/dev/null; brief alpha
  script done-oos clean-oos
  AGENT_VERIFY_CMD=true "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "told about other.txt" contains "$FAKE_DIR/prompt.2" "other.txt"
  check "verified after cleanup" eq "$(st alpha status)" verified
  check "other.txt not committed" test -z "$(git -C ../demo-wt/alpha ls-files other.txt)"
}

t_blocked_stops_for_a_decision() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script blocked
  "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "status blocked" eq "$(st alpha status)" blocked
  check "one call only" eq "$(cat "$FAKE_DIR/calls")" 1
}

t_round_timeout() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script hang
  ROUND_TIMEOUT=2 MAX_FAILS=1 "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "status failed" eq "$(st alpha status)" failed
  check "timeout recorded" contains .agent-loop/tasks/alpha/state "timed out"
}

t_no_verify_command_stops_at_review() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script done-change
  "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "needs-review" eq "$(st alpha status)" needs-review
  check "approve refused without verification" bash -c "! '$S/review.sh' alpha approve 2>/dev/null"
  "$S/review.sh" alpha approve --allow-unverified >/dev/null
  check "approved with explicit override" eq "$(st alpha review)" approved
}

t_parallel_limit() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  "$S/new-task.sh" beta >/dev/null; brief beta
  sleep 60 & holder=$!
  printf 'pid=%s\n' "$holder" >> .agent-loop/tasks/alpha/state
  MAX_PARALLEL=1 "$S/dispatch.sh" beta > out.txt 2>&1
  check "refused over the limit" contains out.txt "MAX_PARALLEL=1"
  kill $holder
}

t_stale_lock_is_reclaimed() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  mkdir .agent-loop/tasks/alpha/lock; echo 999999 > .agent-loop/tasks/alpha/lock/pid
  sed -i.bak 's/^status=.*/status=running/' .agent-loop/tasks/alpha/state && echo pid=999999 >> .agent-loop/tasks/alpha/state
  "$S/status.sh" > out.txt
  check "shown as stalled" contains out.txt stalled
  script done-change
  AGENT_VERIFY_CMD=true "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "resumed after crash" eq "$(st alpha status)" verified
}

t_review_integrate_ship_gates() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script done-change
  export AGENT_VERIFY_CMD=true
  "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "integrate refused without review" bash -c "! '$S/integrate.sh' alpha 2>/dev/null"
  "$S/review.sh" alpha approve "looks good" >/dev/null
  "$S/integrate.sh" alpha >/dev/null
  check "integrated" eq "$(st alpha status)" integrated
  check "integration contains the change" contains ../demo-wt/_integration/work.txt "change"
  check "integration verified" contains .agent-loop/integration.state "verify=pass"
  AGENT_SHIP_CMD='echo "$SHIP_SHA" > shipped.txt' "$S/ship.sh" >/dev/null
  check "shipped the verified sha" eq "$(cat ../demo-wt/_integration/shipped.txt)" "$(git -C ../demo-wt/_integration rev-parse HEAD)"
  check "ship refuses a dirty integration tree" bash -c "! AGENT_SHIP_CMD=true '$S/ship.sh' 2>/dev/null"
}

t_failed_integration_is_rolled_back() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script done-change
  AGENT_VERIFY_CMD=true "$S/dispatch.sh" alpha >/dev/null 2>&1
  AGENT_VERIFY_CMD=true "$S/review.sh" alpha approve >/dev/null
  before=$(git rev-parse codex/integration)
  AGENT_VERIFY_CMD='[ -d ../demo-wt/_integration/never ]' "$S/integrate.sh" alpha --allow-unverified >/dev/null 2>&1
  check "status integration-failed" eq "$(st alpha status)" integration-failed
  check "integration branch unchanged" eq "$(git rev-parse codex/integration)" "$before"
}

t_conflicts_detect_overlap() {
  "$S/new-task.sh" alpha >/dev/null; "$S/new-task.sh" beta >/dev/null
  echo a >> ../demo-wt/alpha/work.txt; echo b >> ../demo-wt/beta/work.txt
  "$S/conflicts.sh" > out.txt
  check "overlap reported" contains out.txt "overlap alpha <-> beta: work.txt"
}

t_stop_kills_a_running_task() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script hang
  ROUND_TIMEOUT=600 "$S/dispatch.sh" alpha --detach >/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(st alpha status)" = running ] && [ -s "$FAKE_DIR/calls" ] && break; sleep 1; done
  pid=$(st alpha pid)
  "$S/stop.sh" alpha >/dev/null
  check "driver gone" bash -c "! kill -0 $pid 2>/dev/null"
  check "no fake codex left" bash -c "! pgrep -f 'fake-codex' >/dev/null"
  check "status stopped" eq "$(st alpha status)" stopped
}

t_shared_git_config_is_protected() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  script set-worktree done-change
  AGENT_VERIFY_CMD=true "$S/dispatch.sh" alpha >/dev/null 2>&1
  check "core.worktree removed again" bash -c "! git config --get core.worktree"
  check "main checkout still its own toplevel" eq "$(git rev-parse --show-toplevel)" "$(pwd -P)"
  check "agent told not to touch git config" contains "$FAKE_DIR/prompt.2" "core.worktree"
  check "task still verified" eq "$(st alpha status)" verified
}

t_dispatch_refuses_a_broken_shared_config() {
  "$S/new-task.sh" alpha >/dev/null; brief alpha
  git config core.worktree /tmp/elsewhere
  "$S/dispatch.sh" alpha > out.txt 2>&1
  check "refused" contains out.txt "core.worktree"
  check "agent never started" test ! -s "$FAKE_DIR/calls"
  git config --unset core.worktree
}

t_status_outputs() {
  "$S/new-task.sh" alpha >/dev/null
  printf '# Tasks\n<!-- hitl:status:start -->\nold\n<!-- hitl:status:end -->\n' > TASKS.md
  "$S/status.sh" --sync TASKS.md >/dev/null
  check "markdown synced" contains TASKS.md "| alpha | created |"
  check "old content replaced" bash -c "! grep -q '^old$' TASKS.md"
  "$S/status.sh" --json > out.json
  check "json parses" python3 -c "import json; [json.loads(l) for l in open('out.json')]"
}

for c in $(declare -F | awk '{print $3}' | grep '^t_'); do run_case "$c"; done
echo
echo "passed: $pass  failed: $fail${failed_names:+ ($failed_names )}"
[ $fail = 0 ]
