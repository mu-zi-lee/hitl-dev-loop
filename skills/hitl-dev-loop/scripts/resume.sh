#!/usr/bin/env bash
# usage: resume.sh <name> [message]
# Resume the task's Codex session. A pending $AGENT_HOME/feedback/<name>.md is
# injected first as new user feedback and then renamed *.sent.<timestamp>.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; msg=${2:-继续推进，不要只汇报进度。全部完成、测试通过并提交后，最终回复以「【已完成】」开头。}
sid=$(task_sid "$name"); [ -n "$sid" ] || { echo "no session for $name" >&2; exit 1; }
fb="$AGENT_HOME/feedback/$name.md"
if [ -f "$fb" ]; then
  msg="用户的新反馈（优先处理；处理完再继续原任务；全部修好、测试通过并提交后，最终回复以「【已完成】」开头）：
$(cat "$fb")

$msg"
  mv "$fb" "$fb.sent.$(date +%s)"
  : > "$(task_final "$name")"
fi
cd "$(task_dir "$name")" || exit 1
sandbox=(); while IFS= read -r line; do sandbox+=("$line"); done < <(codex_sandbox_config)
# shellcheck disable=SC2086
"$CODEX_BIN" exec resume "${sandbox[@]}" $CODEX_EXTRA_ARGS -o "$(task_final "$name")" "$sid" "$msg" >> "$(task_log "$name")" 2>&1
echo "exit $?" >> "$(task_log "$name")"
