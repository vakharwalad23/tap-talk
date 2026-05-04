---
description: Git commit message conventions
globs: *
---

# Commit Conventions

## Format
```
<type>: <subject>
```

Subject line max 50 chars. Imperative mood ("add" not "added").

## Types
- `feat:` — new feature or capability
- `fix:` — bug fix
- `refactor:` — code restructuring, no behavior change
- `perf:` — performance improvement
- `build:` — build system, dependencies, CI
- `docs:` — documentation only
- `style:` — formatting, no logic change
- `chore:` — maintenance, config, cleanup
- `test:` — adding or fixing tests

## Rules
- No `Co-Authored-By` lines.
- No emoji in commit messages.
- One logical change per commit. Split large changes.
- Body optional — add only when "why" isn't obvious from subject.
- Reference issue numbers in body if applicable: `Closes #42`.
- Never commit secrets, build artifacts, or generated files.
