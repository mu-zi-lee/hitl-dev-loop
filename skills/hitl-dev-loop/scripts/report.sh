#!/usr/bin/env bash
# usage: report.sh <name> — markdown summary of a task for the lead agent / user.
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/lib.sh"
name=${1:?task name}; require_task "$name"
dir=$(task_dir "$name"); wt=$(task_wt "$name")
started=$(state_get "$name" started_at 0); elapsed=-
[ "$started" -gt 0 ] && elapsed="$(( ($(now) - started) / 60 )) min"
echo "# Task $name"
echo
echo "- Status: **$(state_get "$name" status)** (report: $(state_get "$name" report_status -))"
echo "- Branch: \`$(state_get "$name" branch)\` at \`$(git -C "$wt" rev-parse --short HEAD)\`, base \`$(state_get "$name" base | cut -c1-12)\`"
echo "- Rounds: $(state_get "$name" rounds 0) · Tokens: $(state_get "$name" tokens 0) · Elapsed: $elapsed"
echo "- Verify: $(state_get "$name" verify_result -) at \`$(state_get "$name" verify_sha | cut -c1-12)\` · Review: $(state_get "$name" review -)"
le=$(state_get "$name" last_error); [ -n "$le" ] && echo "- Last error: $le"
echo
echo "## Changed files"
changed_files "$name" | sed 's/^/- /'
if [ -s "$dir/report.json" ] && command -v python3 >/dev/null; then
  python3 - "$dir/report.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
print("\n## Agent report\n\n" + r.get("summary",""))
for k,title in [("tests","Tests the agent ran"),("unfinished","Unfinished"),("risks","Risks"),("manual_checks","Check by hand")]:
    v=r.get(k) or []
    if not v: continue
    print("\n### "+title)
    for x in v:
        print("- " + (f"`{x['command']}` — {x['result']}" if isinstance(x,dict) else str(x)))
PY
fi
if [ -s "$dir/verify.log" ]; then echo; echo "## Verification log (tail)"; echo '```'; tail -20 "$dir/verify.log"; echo '```'; fi
