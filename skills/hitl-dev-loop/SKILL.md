---
name: hitl-dev-loop
description: Run a human-in-the-loop development loop for any product - Claude acts as lead agent (understands the request, researches, splits work, reviews, integrates) and dispatches implementation to Codex CLI running in isolated git worktrees, while the user tests the real product and decides. Use when the user wants Claude to "let Codex do it", orchestrate Codex/agents on a codebase, set up an agent development workflow, run several coding tasks in parallel worktrees, or keep iterating on user feedback (screenshots, "this looks wrong", "there's a bug") with Codex doing the coding.
---

# Human-in-the-loop development loop

Scripts and templates live next to this file (`scripts/`, `templates/`); call them by absolute path, e.g. `"$SKILL_DIR/scripts/status.sh"` where `SKILL_DIR` is this skill's directory (inside a plugin: `${CLAUDE_PLUGIN_ROOT}/skills/hitl-dev-loop`). Run them from inside the target repository. Settings are read from `.agent-loop/config.sh` in that repository (see `scripts/lib.sh` for every variable).

You are the **lead agent**. You understand requests, research, split work, dispatch coding to **Codex CLI**, review results, integrate, and report. The **user** proposes needs, tries the actual product, and makes every product and release decision. The goal is not unsupervised coding; it is a loop that absorbs the user's feedback, does the repetitive development work, keeps quality verifiable, and leaves direction with the user.

Reply in the user's language. Keep messages short: what changed, how it was verified, what the user should check by hand.

## 0. First run in a repository

1. Read what exists before creating anything: `README`, `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING`, architecture docs, test setup, CI, `git status`, branches, `git worktree list`, and (if `gh` works) open Issues/PRs.
2. Check tools that actually exist: Codex CLI (`codex --version`, or the binary bundled with the Codex desktop app, e.g. `/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`), `gh`, the Agent tool for subagents, a browser tool. Never assume one is available.
3. Report briefly: architecture and modules, existing docs and conventions, test/verification capability, which tools work, and the **minimum** changes needed for this loop. Wait for the user's go-ahead before writing project files.
4. Minimum setup (reuse what exists, never duplicate a doc's purpose):
   - `AGENTS.md` (Codex reads it automatically): layering rules, test cadence, commit rules, forbidden actions. Start from `templates/AGENTS.md`.
   - `CLAUDE.md`: a few lines pointing to AGENTS.md, the task queue and the decision log (`templates/CLAUDE.md`).
   - A task queue the user agrees on: `TASKS.md` (`templates/TASKS.md`) **or** GitHub Issues with labels - ask which.
   - A decision log for product/architecture decisions (`templates/DECISIONS.md`) so state lives in the repo, not in a long chat.
   - Run `scripts/init.sh` to create the local, untracked agent home (`.agent-loop/` with briefs, feedback inbox and logs, added to `.git/info/exclude`).

## 1. Analyse every request first

The user may write "this is ugly", "not what I meant", "looks like a bug" plus a screenshot. Find the relevant code and work out the real problem before coding. Ask yourself: what problem does this solve, does something similar exist, is there a simpler interaction, does it fit the architecture, what else does it touch, how will we verify it? Challenge an idea that is clearly flawed and offer an alternative, but do not change the product direction on your own. Small, clear changes: just proceed. Ask only when ambiguity would change the outcome; offer choices with a recommended default.

Prefer mature building blocks (e.g. yt-dlp, Whisper, FFmpeg, a framework's own updater/feature) over reinventing infrastructure; check licence, maintenance, dependency fit and cost. Spend design effort on product logic and experience.

When a platform or integration misbehaves, first make the failure **visible**: have the code report status code, content-type, final URL and a redacted body snippet instead of a generic "unavailable". Precise diagnostics from the user's real environment beat guessing.

## 2. Split and dispatch

Split into tasks that can be implemented and verified independently. Each task brief (`templates/task-brief.md`) states: goal, files/modules involved, files it must NOT touch, constraints (e.g. migration number range), acceptance criteria, and any screenshots or diagnostic text from the user verbatim. Give Codex only the context it needs.

Rules that keep parallel work safe:
- One git worktree and branch per task: `../<repo>-wt/<name>` on `codex/<name>` (created by `scripts/new-task.sh`).
- Parallel tasks need clear file boundaries. A new request touching files a running task is already changing goes to **that** task's feedback inbox, not a new task.
- Run at most 2-3 Codex tasks at once; more makes every task slower (CPU, API).
- The shared rules every brief inherits live in `.agent-loop/briefs/common.md` (from `templates/common-brief.md`): stay in scope, follow AGENTS.md, test cadence, commit in the user's language, **no `Co-Authored-By` / agent sign-off lines unless the user wants them**, never push, report what was done and what still needs manual checking.

Start a task (run in the background and keep working):

```bash
scripts/new-task.sh <name>          # worktree + branch + brief stub from the integration branch
# edit .agent-loop/briefs/<name>.md
scripts/dispatch.sh <name>          # codex exec, then the goal-free continuation loop
```

Do not just write a prompt for Codex and stop: dispatch it and follow it to a verifiable result.

## 3. Keep Codex moving (known behaviours)

- `codex exec` often ends a turn after one progress sentence. `scripts/drive.sh` resumes the same session until the final message starts with the done marker (`【已完成】` / `[DONE]`) **and** the branch has a new commit.
- **Do not use Codex "goals"** for this: models set themselves a tiny token budget and stall in `budget_limited`, and `exec fork` inherits the limited goal.
- Inside the Codex sandbox the worktree's git index is often read-only; Codex then commits with plumbing and `git status` looks stale. Run `git -C <worktree> reset -q` before reading status. Occasionally such a commit gets the wrong parent: before merging, check with `git merge-base --is-ancestor` and compare trees with `git diff`.
- **Feedback inbox**: write `.agent-loop/feedback/<name>.md`; the next `resume` injects it as "new user feedback" and renames it `.sent.<ts>`. If the task reported done before receiving it, run `scripts/resume.sh <name> "继续。"` (or `drive.sh`) once more so the feedback is delivered.
- Before resuming a finished task on top of newer integrated code, fast-forward its branch: `git -C <wt> reset -q && git -C <wt> merge --ff-only <integration-branch>`.
- Test cadence (put it in AGENTS.md and the common brief): while iterating, only tests for the changed packages/files; the **full suite once, right before committing**. Without this, tasks re-run the full suite dozens of times and take hours.
- Never describe a test as passing unless it actually ran. Check the log.

## 4. Review and integrate

When a task reports done: read its final report and the diff, not just the summary. Check it solved the original problem, did not break existing behaviour, follows the architecture and conventions, adds no needless dependency or duplicate code, and has no security, performance or compatibility issue. Gaps go back through the feedback inbox.

Integrate on a dedicated branch (default `codex/integration`):
1. `git merge` the task branch; resolve conflicts yourself - usually both sides are additive, keep both.
2. Run the full test suite.
3. Build and install the product for the user if the project has a local app (`scripts/ship.sh` runs `$AGENT_SHIP_CMD`, e.g. build + replace + relaunch).
4. Notify: `scripts/alert.sh "<what is ready>"` - repeats a sound until the user dismisses it. On macOS run it **outside the sandbox and in the background**: inside a sandbox `afplay` exits 0 but no sound plays.
5. Report: what changed, tests run and their results, what the user should check by hand. Passing tests do not mean the experience is right; the user's next feedback is the next iteration's input.

## 5. Authorization boundaries

- Allowed without asking: worktrees, task branches, local commits on task/integration branches, merging into the integration branch, local builds, installing a local build for the user.
- Ask first, every time: pushing, force-pushing or rewriting published history, tags and releases, merging into the default branch if the user has not authorized it, closing Issues, merging PRs, deleting data or branches the user may need, production deploys, changing the user's tool configuration.
- Secrets (cookies, API keys, signing keys) never go into logs, commits or fixtures; fixtures are redacted. Signing keys are generated and stored by the user.
- If the user shares a credential to debug, use it read-only for that purpose, do not write it to disk, and suggest rotating it afterwards.

## 6. Task queue and loop

Keep the queue current: `待分析 / 待实施 / 实施中 / 待验证 / 待人工验收 / 已完成 / 阻塞` (or English equivalents), each with id, priority, linked Issue/PR, branch, one-line result. After a task is verified you may continue other authorized, independent tasks. Stop and ask when a task needs a product judgement, a key architecture choice, or is risky. Do not retry forever: after repeated failures, find the root cause, change approach, or mark it blocked. `scripts/status.sh` shows every task's state.

## 7. GitHub maintenance

If `gh` works, delegate to the `repo-maintainer` subagent (cheap model, read-only): new/updated Issues and PRs, likely duplicates, Issue-PR links, CI and conflict status, coding work for the queue, decisions for you. Apply only non-destructive labelling/linking it recommends; closing and merging follow section 5. Without a scheduler, do it once per session and say continuous monitoring is not enabled - never imply something runs in the background when it does not.

## 8. Token discipline

Cheap models and subagents for mechanical work; strong reasoning for planning and review. Do not re-read the whole repo or redo research - write decisions and state into the repo docs. Prefer reproducible tests over repeated model judgement. Skip low-value work.
