#!/usr/bin/env bash
# usage: init.sh — one-time, idempotent setup in a repository.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
mkdir -p "$AGENT_HOME"/briefs "$AGENT_HOME"/feedback "$AGENT_HOME"/tasks
[ -f "$AGENT_HOME/briefs/common.md" ] || cp "$HITL_SKILL_DIR/templates/common-brief.md" "$AGENT_HOME/briefs/common.md"
if [ ! -f "$AGENT_HOME/config.sh" ]; then cat > "$AGENT_HOME/config.sh" <<'CFG'
# hitl-dev-loop settings for this repository (local, not committed).
# Full verification the scheduler runs itself before a task counts as done:
# AGENT_VERIFY_CMD='make test'
# Build + install the product for manual testing (runs in the integration worktree):
# AGENT_SHIP_CMD='make build && ./scripts/install-local.sh'
# CODEX_BIN=/path/to/codex
# CODEX_WRITABLE_DIRS=~/Library/Caches/go-build:~/go:~/.npm   # build caches
# DEFAULT_NETWORK=0        # per task: new-task.sh <name> --network
# AGENT_COMMITS=scheduler  # or "agent"
# MAX_PARALLEL=3  MAX_ROUNDS=15  MAX_FAILS=3  MAX_VERIFY_FAILS=3
# ROUND_TIMEOUT=3600  VERIFY_TIMEOUT=3600  TASK_TIME_BUDGET=0  TOKEN_BUDGET=0
# INTEGRATION_BRANCH=codex/integration
CFG
fi
exclude="$(git_common_dir)/info/exclude"; mkdir -p "$(dirname "$exclude")"
rel=${AGENT_HOME#"$REPO_ROOT"/}
if [ "$rel" != "$AGENT_HOME" ] && ! grep -qxF "/$rel/" "$exclude" 2>/dev/null; then echo "/$rel/" >> "$exclude"; fi
if ! git -C "$REPO_ROOT" rev-parse --verify -q "refs/heads/$INTEGRATION_BRANCH" >/dev/null; then
  git -C "$REPO_ROOT" branch "$INTEGRATION_BRANCH" && echo "created $INTEGRATION_BRANCH at $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
fi
echo "agent home:   $AGENT_HOME"
echo "adapter:      $AGENT_ADAPTER ($(agent_version || echo 'NOT FOUND'))"
echo "worktrees:    $WT_ROOT"
echo "integration:  $INTEGRATION_BRANCH"
echo "verify cmd:   ${AGENT_VERIFY_CMD:-<not set — tasks will stop at needs-review>}"
command -v python3 >/dev/null || command -v jq >/dev/null || echo "note: install python3 or jq for reliable JSON parsing"
git merge-tree --write-tree HEAD HEAD >/dev/null 2>&1 || echo "note: git >= 2.38 enables conflict prediction in conflicts.sh"
