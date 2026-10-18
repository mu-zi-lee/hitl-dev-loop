# HITL development protocol (v0.2)

The skill is one implementation of a tool-agnostic protocol. Any lead agent (Claude Code, another assistant, a human) and any coding agent (Codex CLI, Claude Code headless, others) can take part as long as they respect these artifacts, states and gates.

## Roles

| Role | Does | Never |
|---|---|---|
| **User** | States needs, tests the real product, approves risky actions, decides direction. | — |
| **Lead agent** | Analyses requests, writes briefs, dispatches, reviews diffs and reports, integrates, reports to the user. | Approves its own unverified work; pushes/releases without the user. |
| **Coding agent** | Implements one task in its own worktree, runs targeted tests, returns a structured report. | Commits (by default), touches other tasks' files, pushes, handles secrets. |
| **Scheduler** (scripts) | Runs rounds, delivers feedback, enforces budgets, decides completion, verifies, records state, gates integration and shipping. | Makes product decisions. |

## Artifacts (all under `.agent-loop/`, never committed)

| Path | Content |
|---|---|
| `briefs/common.md` | Rules shared by every task. |
| `briefs/<task>.md` | Task brief: goal, evidence, do, do-not-touch, constraints, acceptance criteria. |
| `briefs/<task>.scope` | Optional allowed paths, one shell glob per line. |
| `feedback/<task>.md` | Pending feedback queue. |
| `tasks/<task>/state` | `key=value` state (see below). |
| `tasks/<task>/report.json` | Latest structured report (schema: `templates/report.schema.json`). |
| `tasks/<task>/feedback.inflight` / `feedback.acked.<ts>` | Feedback being delivered / delivered. |
| `tasks/<task>/rounds/<n>.jsonl` | Raw agent events per round. |
| `tasks/<task>/verify.log`, `log` | Verification output, human-readable task log. |
| `integration.state`, `integration-verify.log`, `ship.log` | Last integration commit + verification; ship history. |

Project-level docs that *are* committed: `AGENTS.md` (rules for coding agents), `CLAUDE.md` (pointer for the lead agent), a task queue (`TASKS.md` or Issues), `DECISIONS.md`.

## Report (coding agent → scheduler)

JSON, schema-enforced where the agent supports it:

```json
{"status": "done | in_progress | blocked", "summary": "…", "changes": [{"path": "…", "why": "…"}],
 "tests": [{"command": "…", "result": "passed | failed | not_run"}],
 "unfinished": ["…"], "risks": ["…"], "manual_checks": ["…"]}
```

`tests` lists only commands that actually ran. `blocked` means a human decision is needed.

## Task states

```
created ─dispatch─▶ running ─┬─▶ verified ──review approve──▶ approved ──integrate──▶ integrated
                             ├─▶ needs-review (no verify command configured)
                             ├─▶ blocked            (agent needs a decision)
                             ├─▶ failed             (MAX_FAILS consecutive agent errors / timeouts)
                             ├─▶ verify-failed      (MAX_VERIFY_FAILS verification or scope failures)
                             ├─▶ budget-exceeded    (wall time or tokens)
                             └─▶ stopped            (MAX_ROUNDS or stop.sh)
review changes ─▶ changes-requested ─dispatch─▶ running
integrate ─▶ conflict | integration-failed (merge undone)
running with a dead driver is reported as stalled; dispatch resumes it.
```

## Completion rule (decided by the scheduler)

A round's work counts as done only if **all** hold:
1. the report says `done`;
2. the worktree has real changes relative to the task base;
3. every changed file is inside `<task>.scope` (if present);
4. the scheduler committed the changes (or, with `AGENT_COMMITS=agent`, the tree is clean);
5. `AGENT_VERIFY_CMD`, run by the scheduler at that commit, passes — the result is recorded with the commit SHA.

Failures in 2–5 are turned into feedback and the agent continues, within the caps.

## Feedback delivery

`pending → inflight → acked`. Pending feedback moves to in-flight when a round starts and is acknowledged only after that round succeeds; a failed or timed-out round resends it.

## Gates

| Step | Requires |
|---|---|
| `review approve` | verification `pass` at the task's current SHA (or explicit `--allow-unverified` after the user agreed) |
| `integrate` | approved review at the current SHA + passing verification at that SHA; merged result must pass verification, otherwise the merge is undone |
| `ship` | integration worktree clean and at the recorded, verified integration SHA |
| push / tag / release / close Issue / merge PR | the user's explicit OK, every time |

## Adapter contract (coding agent integration)

An adapter is a bash file `scripts/adapters/<name>.sh` defining:

- `agent_version` — print the agent's version; non-zero exit if unavailable.
- `agent_run NAME start|resume PROMPT_FILE` — run one round in `$(task_wt NAME)` with the prompt on stdin; write the report JSON to `$(task_dir NAME)/report.json`; on `start` success store the session id with `state_set NAME session …`; add token usage with `state_inc NAME tokens …`; on failure set `last_error`; return 0 on success, 124 on timeout (use `run_with_timeout "$ROUND_TIMEOUT" …`), non-zero otherwise. Respect `state_get NAME network` and `AGENT_COMMITS`.

`codex.sh` is the reference implementation (Codex CLI `exec --json --output-schema`).
