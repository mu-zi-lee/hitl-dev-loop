#!/usr/bin/env bash
# One-time setup in a repository: local agent home, shared brief, integration branch.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
mkdir -p "$AGENT_HOME"/{briefs,feedback,logs}
[ -f "$AGENT_HOME/briefs/common.md" ] || cp "$HERE/../templates/common-brief.md" "$AGENT_HOME/briefs/common.md"
[ -f "$AGENT_HOME/config.sh" ] || cat > "$AGENT_HOME/config.sh" <<'CFG'
# Local overrides for hitl-dev-loop (not committed).
# CODEX_BIN=/path/to/codex
# CODEX_WRITABLE_DIRS=~/Library/Caches/go-build:~/go:~/.npm
# INTEGRATION_BRANCH=codex/integration
# AGENT_SHIP_CMD='make desktop-build && ./scripts/install-local.sh'
# DONE_MARKER='^(【已完成】|\[DONE\])'
CFG
exclude="$(git_common_dir)/info/exclude"
rel=${AGENT_HOME#"$REPO_ROOT"/}
grep -qxF "/$rel/" "$exclude" 2>/dev/null || echo "/$rel/" >> "$exclude"
if ! git -C "$REPO_ROOT" rev-parse --verify -q "$INTEGRATION_BRANCH" >/dev/null; then
  git -C "$REPO_ROOT" branch "$INTEGRATION_BRANCH" && echo "created $INTEGRATION_BRANCH from $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
fi
echo "agent home: $AGENT_HOME"
echo "codex:      $CODEX_BIN ($("$CODEX_BIN" --version 2>/dev/null || echo 'not found'))"
echo "worktrees:  $WT_ROOT"
