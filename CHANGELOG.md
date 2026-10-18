# Changelog

## 0.2.0

Reliability is now enforced by the scheduler scripts instead of the prompt.

- **Structured execution**: Codex runs with `--json` and `--output-schema`; session ids, failures (`turn.failed` + exit code) and token usage come from the event stream, not from grepping logs. Sessions are kept only from successful starts.
- **Scheduler-decided completion**: a task is `verified` only when the report says done, real changes exist, changes stay within the optional scope, the scheduler committed them, and `AGENT_VERIFY_CMD` passed at that commit. Otherwise the reason is fed back automatically.
- **Scheduler commits by default** (`AGENT_COMMITS=scheduler`): the agent no longer needs write access to the shared git directory.
- **Reliable feedback**: `pending → inflight → acked`; failed rounds resend feedback.
- **Limits**: per-round timeout, consecutive-failure circuit breaker, verification-failure cap, max rounds, wall-time and token budgets.
- **Task state** (`.agent-loop/tasks/<name>/state`), per-task locks with stale-lock recovery, `MAX_PARALLEL`, `stalled` detection, `stop.sh` (kills the whole process tree).
- **Gates**: `review.sh` records approval bound to a SHA; `integrate.sh` merges only approved + verified commits in a dedicated integration worktree and rolls back if the merged result fails; `ship.sh` builds only the verified integration SHA.
- **Visibility**: `status.sh` (`--json`, `--markdown`, `--sync TASKS.md`), `report.sh`, `conflicts.sh` (file overlaps + `git merge-tree` conflict prediction).
- **Shared git config guard**: after every round the scheduler restores `core.worktree` / `core.bare` in the shared config if the agent changed them and tells the agent; `dispatch.sh` refuses to start on a config that already sets `core.worktree`; the repository root is derived from `--git-common-dir`, so a tampered `core.worktree` cannot redirect the scripts.
- **Safer defaults**: agent network off by default (`new-task.sh --network` per task).
- **Adapter interface** and a tool-agnostic `PROTOCOL.md`.
- **Tests**: 21 scenarios with a scriptable fake Codex; CI runs shellcheck and tests on Ubuntu and macOS (system bash 3.2).
- Removed `resume.sh` (folded into `drive.sh`); `feedback.sh` replaces writing feedback files by hand.

## 0.1.0

Initial release: skill, Codex dispatch/resume/drive scripts, templates, `repo-maintainer` subagent.
