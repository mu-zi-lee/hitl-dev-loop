# Shared rules for every task (prepended to each task brief)

- Read `AGENTS.md` (and the docs it points to) and follow the project's layering, naming, comment density and idioms. User-facing text in the product's language.
- You work in your own git worktree. Other agents work on other branches in parallel: change only what this task needs; no unrelated refactors or reformatting. If the brief lists a scope, stay inside it.
- Use only the database migration numbers / ids assigned in the brief, if any.
- **Test cadence**: while iterating, run only the tests for what you changed (single package / file / test filter, type-check). Run the full suite at most once, at the end. Never claim a test passed unless it actually ran — list exactly what you ran in the report.
- Add unit tests for new logic. Fixtures must be redacted: no real cookies, tokens, keys or personal data.
- Never commit secrets; never generate, read or commit signing keys. Never push, tag or release.
- Commits: follow the "Scheduler protocol" section at the end of this prompt (by default the scheduler commits for you after its checks — do not run git add/commit yourself). No `Co-Authored-By` or agent sign-off lines.
- When something external fails (an API, a page, a build tool), make the code report the concrete cause (status, content type, final URL, a redacted snippet) instead of a generic error.
- Your final message is the JSON report described in the Scheduler protocol, written in the user's language.
