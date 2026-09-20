# Contributing to TapTalk

Thanks for helping. This page is the short version of how work lands here; the linked rules are the
long version.

## Before you start

- Read [`docs/architecture.md`](docs/architecture.md) for one dictation end to end and
  [`docs/models.md`](docs/models.md) for what has already been measured and rejected.
- Open an issue for anything larger than a fix, so the approach is agreed before the code exists.
- The app is native SwiftUI and Rust. No web technology, no Python, no bundled models, ASCII-only
  source. `CLAUDE.md` lists the constraints; `.claude/rules/` holds the standards.

## Branches

`dev` is the default branch and the only target for pull requests. `main` is release-only and takes
nothing but `dev`, merged by the maintainer. Details in [`docs/branching.md`](docs/branching.md).

1. Fork, then branch from `dev`: `git checkout -b <type>/<what-it-does> dev`.
2. Commit with conventional commits: `feat:`, `fix:`, `perf:`, `build:`, `docs:`, `refactor:`,
   `chore:`, `test:`, `style:`. Subject under 50 characters, imperative, no co-author lines, no
   emoji. One logical change per commit.
3. Open the pull request against `dev`. Say what changed and why, and include the before and after
   numbers for anything on the capture, inference, post-processing or paste path (median of 10 runs
   on a fixed clip, see `.claude/rules/performance.md`).
4. A pull request into `main` from anything but `dev` fails its required check and cannot merge.

## Experiments

Measurement suites, model conversions and research notes go on `experiments/<topic>` branches cut
from `main`. They are pushed and kept, and never merged into `dev` or `main`. Nothing under
`orukeet-coreml/` belongs on `dev` or `main`, and model files never belong in git anywhere. When an
experiment produces a change for the app, open a normal `dev` pull request with app code and docs
only and link the experiment branch.

## Checklist

- [ ] Branch from `dev`, pull request against `dev`.
- [ ] Conventional commits, ASCII-only files (`.claude/rules/ascii.md` has the check command).
- [ ] No `unwrap()` in Rust outside tests, no force-unwrap in Swift outside previews.
- [ ] Resource audit done for anything touching lifecycle or concurrency (`.claude/rules/resources.md`).
- [ ] Measurements attached for anything on the dictation path.
- [ ] No files from any experiment folder, no model weights.

## Review and merge

The maintainer reviews and rebase-merges into `dev`. Releases are `dev` to `main` pull requests
opened and merged by the maintainer. Licensed under the [MIT License](LICENSE); by contributing you
agree your work is licensed the same way.
