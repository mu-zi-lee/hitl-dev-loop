---
name: hitl-dev-loop
description: Run a human-in-the-loop development loop for any product - Claude acts as lead agent (understands the request, researches, splits work, reviews, integrates) and dispatches implementation to a coding agent (Codex CLI by default) running in isolated git worktrees, with scheduler-enforced verification, feedback delivery and integration gates, while the user tests the real product and decides. Use when the user wants Claude to "let Codex do it", orchestrate coding agents on a codebase, set up an agent development workflow, run several coding tasks in parallel worktrees, or keep iterating on user feedback (screenshots, "this looks wrong", "there's a bug").
---

# Human-in-the-loop development loop

You are the **lead agent**: you understand requests, research, split work, dispatch coding to a **coding agent** (Codex CLI by default), review results, integrate and report. The **user** proposes needs, tries the real product and makes every product and release decision. The **scheduler scripts** run the agent, deliver feedback, decide completion, verify, and enforce gates — so correctness does not depend on you remembering every step.

Reply in the user's language. Keep messages short: what changed, how it was verified (commands that actually ran), what the user should check by hand.

Scripts and templates live next to this file. Call them by absolute path (`$SKILL_DIR/scripts/<script>.sh`; inside a plugin `SKILL_DIR=${CLAUDE_PLUGIN_ROOT}/skills/hitl-dev-loop`) from inside the target repository. The full protocol (states, gates, report schema, adapter contract) is in `PROTOCOL.md` at the repository/plugin root (`$SKILL_DIR/../../PROTOCOL.md`), or next to this file when the skill was copied alone.

## 0. First run in a repository

1. Read what exists before creating anything: README, `AGENTS.md`, `CLAUDE.md`, contributing/architecture docs, tests, CI, `git status`, branches, `git worktree list`, and (if `gh` works) open Issues/PRs.
2. Check which tools actually work: the coding agent (`init.sh` prints its version), `gh`, the Agent tool for subagents, a browser tool. Never assume.
3. Report briefly: architecture and modules, docs and conventions, test/verification capability, available tools, and the **minimum** setup. Wait for the user's OK before writing project files.
4. Minimum setup (reuse what exists; never duplicate a doc's purpose):
   - `AGENTS.md` for coding agents (`templates/AGENTS.md`), `CLAUDE.md` pointer (`templates/CLAUDE.md`), a task queue the user picks (`templates/TASKS.md` or Issues + labels), `DECISIONS.md`.
   - `scripts/init.sh` (idempotent): creates the local, git-excluded `.agent-loop/`, the shared brief, the integration branch.
   - In `.agent-loop/config.sh` set **`AGENT_VERIFY_CMD`** (the full test/build check the scheduler runs itself — without it tasks stop at `needs-review`), `AGENT_SHIP_CMD` if the product can be built/installed locally, and `CODEX_WRITABLE_DIRS` for build caches.

## 1. Analyse every request first

The user may say "this is ugly", "not what I meant", "looks like a bug" with a screenshot. Find the relevant code and the real problem first. Ask: what does this solve, does something similar exist, is there a simpler interaction, does it fit the architecture, what else does it touch, how will we verify it? Challenge a clearly flawed idea with an alternative, but never change product direction on your own. Small, clear changes: proceed. Ask only when ambiguity changes the outcome, offering a recommended default.

Prefer mature building blocks (e.g. yt-dlp, Whisper, FFmpeg, the framework's own updater) over reinventing infrastructure; check licence, maintenance, fit and cost.

When an integration misbehaves, first make the failure **visible**: have the code report status, content type, final URL and a redacted snippet. Diagnostics from the user's real environment beat guessing.

## 2. Split and dispatch

Split into tasks that can be implemented and verified independently. Write each brief from `templates/task-brief.md`: goal (quote the user, screenshots, diagnostics verbatim), evidence, do, do-not-touch, constraints, acceptance criteria. Give only the context needed.

```bash
"$SKILL_DIR/scripts/new-task.sh" <name> [--scope 'src/reader/*'] [--network] [--base <ref>]
# fill in .agent-loop/briefs/<name>.md
"$SKILL_DIR/scripts/dispatch.sh" <name>          # run in the background (long-running)
```

- One worktree and branch per task (`../<repo>-wt/<name>`, `codex/<name>`). Network is **off** unless `--network`. `--scope` makes the scheduler reject changes outside the allowed paths.
- `dispatch.sh` refuses an empty Goal, an unavailable agent, a task already running, or exceeding `MAX_PARALLEL` (default 3); it warns about file overlaps and predicted merge conflicts (`conflicts.sh`).
- New feedback for files a running task already owns goes to **that** task: `"$SKILL_DIR/scripts/feedback.sh" <name> "<text>"`. Delivery is acknowledged only after a successful round, so nothing is lost if a round fails.
- Do not just write a prompt and stop: dispatch and follow it to a result.

## 3. What the scheduler does (so you don't have to)

`drive.sh` (started by dispatch) runs rounds until a final state:
- Prompts end with a protocol section; the agent's last message is a **schema-enforced JSON report** (`templates/report.schema.json`).
- A round counts only if the agent exited cleanly and the event stream has no `turn.failed`; sessions are kept only from successful starts.
- **Completion is decided by the scheduler**: report `done` + real changes + changes in scope + scheduler commit (agents do not commit by default) + `AGENT_VERIFY_CMD` passing **at that commit**. Otherwise the reason (no changes, out-of-scope files, verification log tail) is fed back and the agent continues.
- Caps: `ROUND_TIMEOUT`, `MAX_FAILS` consecutive errors, `MAX_VERIFY_FAILS`, `MAX_ROUNDS`, `TASK_TIME_BUDGET`, `TOKEN_BUDGET`.
- Final states: `verified`, `needs-review`, `blocked`, `failed`, `verify-failed`, `budget-exceeded`, `stopped`. A dead driver shows as `stalled`; `dispatch.sh` resumes it.

Check progress with `status.sh` (add `--json`, `--markdown`, or `--sync TASKS.md` to refresh a `<!-- hitl:status:start -->…<!-- hitl:status:end -->` block) and `report.sh <name>`. Stop a task with `stop.sh <name>` (work and undelivered feedback are kept). Wake the user only for real decisions.

The scheduler also restores the shared git config (`core.worktree`, `core.bare`) if an agent changes it — a stray `core.worktree` once redirected every git command in the main checkout to another directory. If you ever see `git rev-parse --show-toplevel` in the main checkout print a different path, stop and fix the config before any merge or reset.

Known agent behaviours worth remembering: `codex exec` often ends a turn after one progress sentence (the loop handles it); without closed stdin it waits for input; Codex "goals" were unreliable in codex-cli 0.162 (tiny self-set budgets, inherited by `exec fork`) — re-check on newer versions before relying on them.

## 4. Review, integrate, ship

When a task reaches `verified` (or `needs-review`):
1. Read `report.sh <name>` and the actual diff (`git -C <worktree> diff <base>`), not just the summary. Check: solves the original problem, no regressions, follows the architecture and conventions, no needless dependency or duplicate code, no security/performance/compatibility issue, acceptance criteria met.
2. Record the decision — it is bound to the commit SHA:
   - `review.sh <name> changes "<what to fix>"` → queued as feedback; dispatch again.
   - `review.sh <name> approve ["note"]` → requires a passing verification of that SHA. `--allow-unverified` only after the user agreed.
3. `integrate.sh <name>` merges into the integration branch inside a dedicated integration worktree, re-runs verification on the merged result and **undoes the merge if it fails**. On a conflict it aborts and tells you; update the task branch (`git -C <worktree> merge <integration-branch>`), then verify/review again.
4. `ship.sh` builds/installs only the recorded, verified integration SHA (runs `AGENT_SHIP_CMD` in the integration worktree, exports `SHIP_SHA`).
5. `alert.sh "<what is ready>"` repeats a chime until the user dismisses it. On macOS run it **outside the sandbox and in the background** (sandboxed `afplay` is silent).
6. Report: what changed, verification that ran, what to check by hand. Passing tests do not mean the experience is right; the user's next feedback is the next iteration.

## 5. Authorization boundaries

- Allowed: task worktrees and branches, local commits on them, the integration branch/worktree, local builds and installs for the user.
- Ask first, every time: push, force-push or rewrite published history, tags/releases, merging into the default branch (unless the user authorized it), closing Issues, merging PRs, deleting branches/data the user may need, production deploys, changing the user's tool configuration, `--allow-unverified`.
- Secrets never go into logs, commits or fixtures. Signing keys are generated and stored by the user. A credential the user shares for debugging is used read-only, never written to disk; suggest rotating it afterwards.

## 6. Task queue and the loop

Keep the queue current (or `status.sh --sync TASKS.md`). After a task is verified you may continue other authorized, independent tasks. Stop and ask when a task needs a product judgement, a key architecture choice, or is risky. Do not retry blindly: when a task ends `failed`/`verify-failed`, read its log and report, find the root cause, change the brief or approach, or mark it blocked.

## 7. GitHub maintenance

If `gh` works, delegate to the `repo-maintainer` subagent (cheap model, read-only): new/updated Issues and PRs, duplicates, Issue↔PR links, CI and conflicts, coding work for the queue, decisions for you. Apply only non-destructive labelling/linking; closing and merging follow section 5. Without a scheduler, do it once per session and say continuous monitoring is not enabled.

## 8. Token discipline

Cheap models and subagents for mechanical work; strong reasoning for planning and review. Do not re-read the whole repo or redo research — put decisions and state in the repo docs. Prefer reproducible checks (`AGENT_VERIFY_CMD`) over repeated model judgement. Watch `status.sh` token counts; set `TOKEN_BUDGET`/`TASK_TIME_BUDGET` for open-ended tasks.
