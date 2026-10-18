# AGENTS.md

Instructions for coding agents (Codex, Claude, others) working in this repository.

## Project
<!-- One paragraph: what the product is, who uses it, the decided product direction. -->

## Architecture
<!-- Modules and their responsibilities, dependency direction, where new code goes. Link to the architecture doc instead of repeating it. -->

## Commands
- Build:
- Unit tests (single package/file):
- Full test suite (run once before committing):
- Lint / type-check:

## Rules
- Follow the existing layering and code style; change only what the task needs.
- Test cadence: targeted tests while iterating, full suite once before committing.
- Add tests for new logic; redact fixtures.
- Commit messages in <language>; no agent sign-off / Co-Authored-By lines.
- Never push, tag, release, or touch secrets/signing keys.
- Report failures with concrete diagnostics (status, content-type, final URL, redacted snippet) rather than generic messages.

## Known pitfalls
<!-- Hard-won facts about external platforms, frameworks, environments. -->
