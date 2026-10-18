#!/usr/bin/env bash
# Agent adapter for OpenAI Codex CLI. See PROTOCOL.md for the adapter contract:
#   agent_version                      -> prints the agent version, fails if unavailable
#   agent_run NAME start|resume FILE   -> one agent round with FILE as the prompt;
#       writes the structured report to $(task_dir NAME)/report.json,
#       records session/tokens/last_error in the task state,
#       returns 0 on success, 124 on timeout, non-zero on any failure.
# shellcheck disable=SC2034

if [ -z "${CODEX_BIN:-}" ]; then
  if command -v codex >/dev/null 2>&1; then CODEX_BIN=$(command -v codex)
  elif [ -x /Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex ]; then
    CODEX_BIN=/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
  else
    CODEX_BIN=codex
  fi
fi

agent_version() { "$CODEX_BIN" --version 2>/dev/null </dev/null; }

# Writable roots for the sandbox (beyond the worktree itself).
_codex_roots() {
  local IFS=: d
  if [ "$AGENT_COMMITS" = agent ]; then git_common_dir; fi
  for d in $CODEX_WRITABLE_DIRS; do [ -n "$d" ] && echo "${d/#\~/$HOME}"; done
  return 0
}

# Summarise a JSONL event file into key=value lines: session, failed, error, tokens.
_codex_parse_events() {
  local f=$1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$f" <<'PY'
import json,sys
sid=""; failed=0; err=""; tokens=0
for line in open(sys.argv[1], errors="replace"):
    line=line.strip()
    if not line.startswith("{"): continue
    try: e=json.loads(line)
    except Exception: continue
    t=e.get("type","")
    if t=="thread.started": sid=e.get("thread_id",sid)
    elif t=="turn.failed":
        failed=1; err=(e.get("error") or {}).get("message","turn failed")
    elif t=="error" and not err: err=e.get("message","")
    elif t=="turn.completed":
        u=e.get("usage") or {}
        tokens+=int(u.get("input_tokens",0))+int(u.get("output_tokens",0))
print("session="+sid); print("failed=%d"%failed); print("tokens=%d"%tokens)
print("error="+err.replace("\n"," ")[:300])
PY
  else
    printf 'session=%s\n' "$(grep -m1 '"thread.started"' "$f" | sed 's/.*"thread_id":[[:space:]]*"\([^"]*\)".*/\1/')"
    if grep -q '"turn.failed"' "$f"; then echo failed=1; else echo failed=0; fi
    echo tokens=0
    printf 'error=%s\n' "$(grep -m1 '"turn.failed"' "$f" | sed 's/.*"message":[[:space:]]*"\([^"]*\)".*/\1/' | cut -c1-300)"
  fi
}

agent_run() { # name mode prompt_file
  local name=$1 mode=$2 prompt=$3 dir wt round events stderr rc net sid summary
  dir=$(task_dir "$name"); wt=$(task_wt "$name")
  round=$(state_get "$name" rounds 0)
  mkdir -p "$dir/rounds"
  events="$dir/rounds/$round.jsonl"; stderr="$dir/rounds/$round.stderr"
  : > "$dir/report.json"
  net=false; [ "$(state_get "$name" network 0)" = 1 ] && net=true

  local roots=() r
  while IFS= read -r r; do [ -n "$r" ] && roots+=("$r"); done < <(_codex_roots)

  if [ "$mode" = start ]; then
    local adds=()
    for r in ${roots[@]+"${roots[@]}"}; do adds+=(--add-dir "$r"); done
    # shellcheck disable=SC2086
    run_with_timeout "$ROUND_TIMEOUT" "$CODEX_BIN" exec --json -C "$wt" -s workspace-write \
      -c "sandbox_workspace_write.network_access=$net" ${adds[@]+"${adds[@]}"} $CODEX_EXTRA_ARGS \
      --output-schema "$REPORT_SCHEMA" -o "$dir/report.json" - < "$prompt" > "$events" 2> "$stderr"
    rc=$?
  else
    sid=$(state_get "$name" session)
    [ -n "$sid" ] || { state_set "$name" last_error "no session to resume"; return 1; }
    local list="" sep=""
    for r in ${roots[@]+"${roots[@]}"}; do list="$list$sep\"$r\""; sep=,; done
    # shellcheck disable=SC2086
    (cd "$wt" && run_with_timeout "$ROUND_TIMEOUT" "$CODEX_BIN" exec resume --json \
      -c 'sandbox_mode="workspace-write"' -c "sandbox_workspace_write.network_access=$net" \
      -c "sandbox_workspace_write.writable_roots=[$list]" $CODEX_EXTRA_ARGS \
      --output-schema "$REPORT_SCHEMA" -o "$dir/report.json" "$sid" - < "$prompt" > "$events" 2> "$stderr")
    rc=$?
  fi

  summary=$(_codex_parse_events "$events")
  state_inc "$name" tokens "$(printf '%s\n' "$summary" | sed -n 's/^tokens=//p')"
  if [ $rc = 0 ] && printf '%s\n' "$summary" | grep -q '^failed=1'; then rc=1; fi
  # A failed start still emits thread.started; only keep sessions that worked.
  sid=$(printf '%s\n' "$summary" | sed -n 's/^session=//p')
  if [ $rc = 0 ] && [ "$mode" = start ] && [ -n "$sid" ]; then state_set "$name" session "$sid"; fi
  if [ $rc != 0 ]; then
    local err; err=$(printf '%s\n' "$summary" | sed -n 's/^error=//p')
    [ -n "$err" ] || err=$(grep -v -e rmcp -e '^Reading additional input' "$stderr" 2>/dev/null | tail -2 | tr '\n' ' ' | cut -c1-300)
    [ $rc = 124 ] && err="round timed out after ${ROUND_TIMEOUT}s"
    state_set "$name" last_error "${err:-agent exited with $rc}"
  fi
  return $rc
}
