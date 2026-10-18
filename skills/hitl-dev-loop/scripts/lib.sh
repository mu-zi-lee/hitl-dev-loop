#!/usr/bin/env bash
# Shared settings for the hitl-dev-loop scripts. Override any of them in
# $AGENT_HOME/config.sh (created by init.sh) or in the environment.
set -u

REPO_ROOT=${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}
[ -n "$REPO_ROOT" ] || { echo "run inside a git repository" >&2; exit 1; }
AGENT_HOME=${AGENT_HOME:-$REPO_ROOT/.agent-loop}
[ -f "$AGENT_HOME/config.sh" ] && . "$AGENT_HOME/config.sh"

REPO_NAME=$(basename "$REPO_ROOT")
WT_ROOT=${WT_ROOT:-$(dirname "$REPO_ROOT")/$REPO_NAME-wt}
INTEGRATION_BRANCH=${INTEGRATION_BRANCH:-codex/integration}
TASK_BRANCH_PREFIX=${TASK_BRANCH_PREFIX:-codex/}
DONE_MARKER=${DONE_MARKER:-'^(【已完成】|\[DONE\])'}
MAX_ROUNDS=${MAX_ROUNDS:-15}
CODEX_NETWORK=${CODEX_NETWORK:-1}
# Extra writable directories for the Codex sandbox, colon separated
# (build caches such as ~/Library/Caches/go-build:~/go:~/.npm).
CODEX_WRITABLE_DIRS=${CODEX_WRITABLE_DIRS:-}
CODEX_EXTRA_ARGS=${CODEX_EXTRA_ARGS:-}

if [ -z "${CODEX_BIN:-}" ]; then
  if command -v codex >/dev/null 2>&1; then CODEX_BIN=$(command -v codex)
  elif [ -x /Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex ]; then
    CODEX_BIN=/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
  else
    CODEX_BIN=codex
  fi
fi

task_dir()  { echo "$WT_ROOT/$1"; }
task_log()  { echo "$AGENT_HOME/logs/$1.log"; }
task_final(){ echo "$AGENT_HOME/logs/$1.final.md"; }
task_sid()  { cat "$AGENT_HOME/logs/$1.sid" 2>/dev/null; }

# The worktree's git metadata lives in the main repository; Codex needs it
# writable to commit.
git_common_dir() { (cd "$REPO_ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd); }

# Sandbox flags shared by exec and resume (resume does not accept -s/--add-dir).
codex_sandbox_config() {
  local common roots
  common=$(git_common_dir)
  roots="\"$common\""
  local IFS=:
  for d in $CODEX_WRITABLE_DIRS; do [ -n "$d" ] && roots="$roots,\"${d/#\~/$HOME}\""; done
  printf '%s\n' -c 'sandbox_mode="workspace-write"' \
    -c "sandbox_workspace_write.network_access=$([ "$CODEX_NETWORK" = 1 ] && echo true || echo false)" \
    -c "sandbox_workspace_write.writable_roots=[$roots]"
}
