#!/usr/bin/env bash
# Shared library for the hitl-dev-loop scripts (bash 3.2 compatible).
# Every setting can be overridden in $AGENT_HOME/config.sh or the environment.
set -u

HITL_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HITL_SKILL_DIR=$(cd "$HITL_LIB_DIR/.." && pwd)

# The main checkout is the parent of the shared git directory. This holds from
# any task worktree and stays correct even if core.worktree was tampered with
# (which makes --show-toplevel lie).
_hitl_common=$(git ${REPO_ROOT:+-C "$REPO_ROOT"} rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if [ -z "$_hitl_common" ]; then echo "hitl: run inside a git repository" >&2; exit 1; fi
REPO_ROOT=$(cd "$_hitl_common/.." && pwd)
AGENT_HOME=${AGENT_HOME:-$REPO_ROOT/.agent-loop}
# shellcheck disable=SC1091
[ -f "$AGENT_HOME/config.sh" ] && . "$AGENT_HOME/config.sh"

REPO_NAME=$(basename "$REPO_ROOT")
WT_ROOT=${WT_ROOT:-$(dirname "$REPO_ROOT")/$REPO_NAME-wt}
INTEGRATION_BRANCH=${INTEGRATION_BRANCH:-codex/integration}
INTEGRATION_WT=${INTEGRATION_WT:-$WT_ROOT/_integration}
TASK_BRANCH_PREFIX=${TASK_BRANCH_PREFIX:-codex/}
AGENT_ADAPTER=${AGENT_ADAPTER:-codex}

# Who commits task work: "scheduler" (default; the agent only edits files and
# cannot write git metadata) or "agent" (the agent commits; the shared git
# directory is then writable from its sandbox).
AGENT_COMMITS=${AGENT_COMMITS:-scheduler}

MAX_PARALLEL=${MAX_PARALLEL:-3}          # running tasks at once
MAX_ROUNDS=${MAX_ROUNDS:-15}             # agent rounds per drive
MAX_FAILS=${MAX_FAILS:-3}                # consecutive agent errors before giving up
MAX_VERIFY_FAILS=${MAX_VERIFY_FAILS:-3}  # failed verifications before giving up
ROUND_TIMEOUT=${ROUND_TIMEOUT:-3600}     # seconds per agent round
VERIFY_TIMEOUT=${VERIFY_TIMEOUT:-3600}   # seconds per verification run
TASK_TIME_BUDGET=${TASK_TIME_BUDGET:-0}  # seconds of wall time per task, 0 = unlimited
TOKEN_BUDGET=${TOKEN_BUDGET:-0}          # input+output tokens per task, 0 = unlimited
DEFAULT_NETWORK=${DEFAULT_NETWORK:-0}    # agent network access for new tasks
AGENT_VERIFY_CMD=${AGENT_VERIFY_CMD:-}   # full verification, run by the scheduler
AGENT_SHIP_CMD=${AGENT_SHIP_CMD:-}       # build/install for manual testing
CODEX_WRITABLE_DIRS=${CODEX_WRITABLE_DIRS:-}  # extra sandbox-writable dirs, colon separated
CODEX_EXTRA_ARGS=${CODEX_EXTRA_ARGS:-}

REPORT_SCHEMA=${REPORT_SCHEMA:-$HITL_SKILL_DIR/templates/report.schema.json}

die()  { echo "hitl: $*" >&2; exit 1; }
now()  { date +%s; }
stamp(){ date '+%Y-%m-%d %H:%M:%S'; }

valid_name() { case "$1" in ''|*[!a-z0-9-]*) return 1;; *) return 0;; esac; }
task_dir()   { echo "$AGENT_HOME/tasks/$1"; }
task_wt()    { echo "$WT_ROOT/$1"; }
task_log()   { echo "$(task_dir "$1")/log"; }
require_task() {
  valid_name "$1" || die "invalid task name '$1' (lowercase letters, digits, dashes)"
  [ -f "$(task_dir "$1")/state" ] || die "unknown task '$1' (run new-task.sh)"
}
tlog() { local name=$1; shift; printf '[%s] %s\n' "$(stamp)" "$*" >> "$(task_log "$name")"; }

# ---- state: one key=value file per task, replaced atomically ----------------
state_get() { # name key [default]
  local v
  v=$(grep -m1 "^$2=" "$(task_dir "$1")/state" 2>/dev/null | cut -d= -f2-)
  printf '%s' "${v:-${3:-}}"
}
state_set() { # name key value
  local f tmp v
  f="$(task_dir "$1")/state"; tmp="$f.tmp.$$"
  v=$(printf '%s' "$3" | tr '\n' ' ')
  { grep -v "^$2=" "$f" 2>/dev/null; printf '%s=%s\n' "$2" "$v"; } > "$tmp" && mv "$tmp" "$f"
}
state_inc() { # name key [by]
  local v; v=$(state_get "$1" "$2" 0); state_set "$1" "$2" $((v + ${3:-1}))
}

# ---- processes and locks ----------------------------------------------------
pid_alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

# lock_acquire DIR: mkdir-based lock holding our pid; stale locks are reclaimed.
lock_acquire() {
  local dir=$1 holder
  if mkdir "$dir" 2>/dev/null; then echo $$ > "$dir/pid"; return 0; fi
  holder=$(cat "$dir/pid" 2>/dev/null)
  if pid_alive "$holder"; then return 1; fi
  rm -rf "$dir"; mkdir "$dir" 2>/dev/null || return 1; echo $$ > "$dir/pid"
}
lock_release() { rm -rf "$1"; }

# kill_tree PID [SIGNAL]: signal a process and all of its descendants.
kill_tree() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c" "${2:-TERM}"; done
  kill -"${2:-TERM}" "$1" 2>/dev/null
  return 0
}

# run_with_timeout SECONDS cmd... — 124 on timeout, otherwise the command's status.
run_with_timeout() {
  local secs=$1 pid watcher rc flag; shift
  flag="${TMPDIR:-/tmp}/hitl-timeout.$$.$RANDOM"; rm -f "$flag"
  # Explicit <&0: without it a background job's stdin becomes /dev/null.
  "$@" <&0 & pid=$!
  ( sleep "$secs"; : > "$flag"; kill_tree "$pid" TERM; sleep 5; kill_tree "$pid" KILL ) &
  watcher=$!
  wait "$pid"; rc=$?
  kill_tree "$watcher" TERM; wait "$watcher" 2>/dev/null
  if [ -e "$flag" ]; then rc=124; rm -f "$flag"; fi
  return $rc
}

# ---- JSON (python3, then jq, then a regex for flat string fields) ----------
json_get() { # file key -> top-level value (strings raw, others as JSON)
  local f=$1 k=$2
  [ -s "$f" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
if not isinstance(d,dict) or sys.argv[2] not in d: sys.exit(1)
v=d[sys.argv[2]]
print(v if isinstance(v,str) else json.dumps(v,ensure_ascii=False))' "$f" "$k"
  elif command -v jq >/dev/null 2>&1; then
    jq -er --arg k "$k" 'if has($k) then .[$k] | (if type=="string" then . else tojson end) else error end' "$f"
  else
    sed -n "s/.*\"$k\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$f" | head -1 | grep .
  fi
}

# ---- git --------------------------------------------------------------------
git_common_dir() { git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir; }
# Agents must not change the shared repository config. A stray core.worktree
# (seen in practice) makes every git command in the main checkout act on some
# other directory. Snapshot the guarded keys and restore them after each round.
git_config_file() { echo "$(git_common_dir)/config"; }
git_config_snapshot() {
  git config -f "$(git_config_file)" --get-regexp '^core\.(worktree|bare)$' 2>/dev/null
  return 0
}
git_config_restore() { # baseline snapshot; returns 1 if something had to be repaired
  local cfg now key val; cfg=$(git_config_file); now=$(git_config_snapshot)
  [ "$now" = "$1" ] && return 0
  for key in core.worktree core.bare; do
    val=$(printf '%s\n' "$1" | sed -n "s/^$key //p")
    if [ -n "$val" ]; then git config -f "$cfg" "$key" "$val"; else git config -f "$cfg" --unset-all "$key" 2>/dev/null; fi
  done
  return 1
}

# Files changed by a task: committed since its base, plus staged, unstaged and untracked.
changed_files() {
  local wt base; wt=$(task_wt "$1"); base=$(state_get "$1" base)
  { git -C "$wt" diff --name-only "$base" -- 2>/dev/null
    git -C "$wt" ls-files --others --exclude-standard 2>/dev/null; } | sort -u
}
has_changes() { [ -n "$(changed_files "$1")" ]; }
worktree_dirty() { [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]; }

# Files outside briefs/<name>.scope (one shell glob per line; '*' also matches '/').
out_of_scope() {
  local scope f g ok; scope="$AGENT_HOME/briefs/$1.scope"
  [ -s "$scope" ] || return 0
  changed_files "$1" | while IFS= read -r f; do
    ok=0
    while IFS= read -r g; do
      case "$g" in ''|'#'*) continue;; esac
      # shellcheck disable=SC2254
      case "$f" in $g) ok=1; break;; esac
    done < "$scope"
    [ $ok = 1 ] || echo "$f"
  done
}

# ---- feedback queue: pending -> inflight -> acked ---------------------------
feedback_pending()  { echo "$AGENT_HOME/feedback/$1.md"; }
feedback_inflight() { echo "$(task_dir "$1")/feedback.inflight"; }
# Move pending feedback into the in-flight slot; it stays there until a round succeeds.
feedback_take() {
  local p i; p=$(feedback_pending "$1"); i=$(feedback_inflight "$1")
  if [ -s "$p" ]; then cat "$p" >> "$i"; rm -f "$p"; fi
  [ -s "$i" ]
}
feedback_ack() {
  local i; i=$(feedback_inflight "$1")
  if [ -s "$i" ]; then mv "$i" "$(task_dir "$1")/feedback.acked.$(now)"; fi
  return 0
}
feedback_add() { # name text
  local p; p=$(feedback_pending "$1"); mkdir -p "$(dirname "$p")"
  printf '\n### %s\n%s\n' "$(stamp)" "$2" >> "$p"
}

running_tasks() { # names of tasks whose driver process is alive
  local d n
  for d in "$AGENT_HOME"/tasks/*/; do
    [ -f "$d/state" ] || continue
    n=$(basename "$d")
    if pid_alive "$(state_get "$n" pid)"; then echo "$n"; fi
  done
  return 0
}

# shellcheck disable=SC1090
. "$HITL_LIB_DIR/adapters/$AGENT_ADAPTER.sh" || die "unknown adapter $AGENT_ADAPTER"
