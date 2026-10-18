#!/usr/bin/env bash
# usage: alert.sh "<message>" — repeat a chime until the user dismisses it (max 30 min).
# On macOS run it OUTSIDE any sandbox and in the background: in a sandbox afplay
# exits 0 but no sound reaches the speakers.
msg=${1:-Work is ready for review}
title=${ALERT_TITLE:-hitl-dev-loop}
if [ "$(uname)" = Darwin ]; then
  ( while true; do afplay /System/Library/Sounds/Glass.aiff; sleep 4; done ) &
  loop=$!
  osascript -e "display dialog \"${msg//\"/\\\"}\" with title \"$title\" buttons {\"Stop / 停止提示音\"} default button 1 with icon note giving up after 1800" >/dev/null 2>&1
  kill "$loop" 2>/dev/null; pkill -P "$loop" 2>/dev/null; true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send -u critical "$title" "$msg"
  command -v paplay >/dev/null && paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null
else
  printf '\a%s: %s\n' "$title" "$msg"
fi
