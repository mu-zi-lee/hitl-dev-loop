# Shared rules for every task (prepended to each task brief)

- Read `AGENTS.md` (and the architecture/contributing docs it points to) and follow the project's layering, naming, comment density and idioms. User-facing text in the product's language.
- You work on your own git worktree and branch. Other agents work on other branches in parallel: change only files needed for this task; no unrelated refactors or reformatting.
- Use only the database migration numbers / ids assigned in the task brief, if any.
- **Test cadence**: while iterating, run only the tests for what you changed (single package / file / `-run` filter, type-check). Run the **full** test suite **once**, right before committing. If it fails, fix and run it once more. Never claim a test passed unless it actually ran.
- Add unit tests for new logic. Fixtures must be redacted: no real cookies, tokens, keys or personal data.
- Never commit secrets. Never generate, read or commit signing keys.
- Commit with clear messages in the user's language. **Do not add `Co-Authored-By` or any agent sign-off lines.** Never push, tag or release.
- Final reply: start with `【已完成】` (or `[DONE]`), then list what you did, key files, test commands you ran with their results, what is unfinished or risky, and what the user must verify by hand.
