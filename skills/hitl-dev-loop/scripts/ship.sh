#!/usr/bin/env bash
# usage: ship.sh [--allow-unverified]
# Builds/installs the verified integration commit for manual testing by running
# $AGENT_SHIP_CMD inside the integration worktree (never in a task worktree or
# a random checkout). SHIP_SHA is exported for the command.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
allow=0; [ "${1:-}" = --allow-unverified ] && allow=1
[ -n "$AGENT_SHIP_CMD" ] || die "set AGENT_SHIP_CMD in $AGENT_HOME/config.sh"
[ -d "$INTEGRATION_WT" ] || die "no integration worktree yet (integrate.sh a task first)"
worktree_dirty "$INTEGRATION_WT" && die "integration worktree has uncommitted changes"
head=$(git -C "$INTEGRATION_WT" rev-parse HEAD)
st="$AGENT_HOME/integration.state"
rec_sha=$(grep -m1 '^sha=' "$st" 2>/dev/null | cut -d= -f2)
rec_verify=$(grep -m1 '^verify=' "$st" 2>/dev/null | cut -d= -f2)
if [ "$rec_sha" != "$head" ] || [ "$rec_verify" != pass ]; then
  [ $allow = 1 ] || die "integration HEAD ${head:0:12} is not a verified integration (recorded: ${rec_sha:0:12} ${rec_verify:-none})"
fi
echo "shipping ${head:0:12}"
(cd "$INTEGRATION_WT" && SHIP_SHA=$head bash -c "$AGENT_SHIP_CMD") < /dev/null
rc=$?
printf '%s sha=%s exit=%s\n' "$(stamp)" "$head" "$rc" >> "$AGENT_HOME/ship.log"
exit $rc
