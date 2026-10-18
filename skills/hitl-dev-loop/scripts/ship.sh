#!/usr/bin/env bash
# usage: ship.sh — build and install the product locally for manual testing.
# Runs $AGENT_SHIP_CMD from the repository root (set it in $AGENT_HOME/config.sh),
# e.g. a build plus "quit the running app, replace it, relaunch".
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
[ -n "${AGENT_SHIP_CMD:-}" ] || { echo "set AGENT_SHIP_CMD in $AGENT_HOME/config.sh" >&2; exit 1; }
cd "$REPO_ROOT" && bash -c "$AGENT_SHIP_CMD"
