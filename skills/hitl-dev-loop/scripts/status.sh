#!/usr/bin/env bash
# usage: status.sh [--json | --markdown | --sync FILE]
# One row per task. A task whose driver died while "running" shows as "stalled"
# (run dispatch.sh to resume it). --sync replaces the block between
# <!-- hitl:status:start --> and <!-- hitl:status:end --> in FILE (e.g. TASKS.md).
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
mode=${1:-table}
rows() { # name|status|running|rounds|tokens|changed|verify|review|feedback|updated|last_error
  local d n st run fb vr upd
  for d in "$AGENT_HOME"/tasks/*/; do
    [ -f "$d/state" ] || continue
    n=$(basename "$d")
    st=$(state_get "$n" status); run=no
    if pid_alive "$(state_get "$n" pid)"; then run=yes; elif [ "$st" = running ]; then st=stalled; fi
    fb=-; [ -s "$(feedback_pending "$n")" ] && fb=pending; [ -s "$(feedback_inflight "$n")" ] && fb=inflight
    vr=$(state_get "$n" verify_result -)
    [ "$vr" != - ] && [ "$(state_get "$n" verify_sha)" != "$(git -C "$(task_wt "$n")" rev-parse HEAD 2>/dev/null)" ] && vr="$vr(old)"
    upd=$(date -r "$(task_log "$n")" '+%m-%d %H:%M' 2>/dev/null || echo -)
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$n" "$st" "$run" "$(state_get "$n" rounds 0)" \
      "$(state_get "$n" tokens 0)" "$(changed_files "$n" | grep -c .)" "$vr" "$(state_get "$n" review -)" \
      "$fb" "$upd" "$(state_get "$n" last_error)"
  done
}
markdown() {
  echo '| Task | Status | Running | Rounds | Tokens | Files | Verify | Review | Feedback | Updated |'
  echo '|---|---|---|---|---|---|---|---|---|---|'
  rows | while IFS='|' read -r n st run r t c v rv fb u _; do
    echo "| $n | $st | $run | $r | $t | $c | $v | $rv | $fb | $u |"
  done
}
case "$mode" in
  table)
    printf '%-20s %-18s %-4s %-6s %-9s %-5s %-11s %-9s %-8s %s\n' TASK STATUS RUN ROUNDS TOKENS FILES VERIFY REVIEW FEEDBACK UPDATED
    rows | while IFS='|' read -r n st run r t c v rv fb u err; do
      printf '%-20s %-18s %-4s %-6s %-9s %-5s %-11s %-9s %-8s %s\n' "$n" "$st" "$run" "$r" "$t" "$c" "$v" "$rv" "$fb" "$u"
      case "$st" in failed|blocked|stalled|verify-failed|conflict|integration-failed|budget-exceeded|stopped)
        [ -n "$err" ] && echo "    └ $err";; esac
    done
    "$HERE/conflicts.sh" --quiet || true ;;
  --json)
    rows | while IFS='|' read -r n st run r t c v rv fb u err; do
      printf '{"task":"%s","status":"%s","running":%s,"rounds":%s,"tokens":%s,"files":%s,"verify":"%s","review":"%s","feedback":"%s","updated":"%s","last_error":"%s"}\n' \
        "$n" "$st" "$([ "$run" = yes ] && echo true || echo false)" "$r" "$t" "$c" "$v" "$rv" "$fb" "$u" "$(printf '%s' "$err" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    done ;;
  --markdown) markdown ;;
  --sync)
    file=${2:?file}; [ -f "$file" ] || die "no such file $file"
    grep -q '<!-- hitl:status:start -->' "$file" || die "add <!-- hitl:status:start --> and <!-- hitl:status:end --> markers to $file"
    tmp="$file.tmp.$$"; tbl="$file.table.$$"; markdown > "$tbl"
    awk -v tf="$tbl" '/<!-- hitl:status:start -->/{print; while ((getline l < tf) > 0) print l; skip=1; next} /<!-- hitl:status:end -->/{skip=0} !skip' "$file" > "$tmp" && mv "$tmp" "$file"
    rm -f "$tbl"
    echo "updated $file" ;;
  *) die "usage: status.sh [--json | --markdown | --sync FILE]" ;;
esac
