# Branching Standards

## Flow
- `main` is the repository's default branch and holds release history. `dev` is the working branch:
  every change lands on `dev` through a pull request from a `<type>/<what-it-does>` branch. Open
  those pull requests with `--base dev`; `gh pr create` and the GitHub UI default to `main`.
- `main` is release-only. The only thing that reaches `main` is `dev`, moved by the maintainer through
  a pull request from `dev` merged with "Create a merge commit". Branch protection requires that pull
  request, the `head-is-dev` check and the `no-experiment-paths` check, and applies to administrators
  too. The `protect-main` ruleset allows merge commits only.
- Never squash or rebase `dev` into `main`: both copy `dev`'s commits instead of moving them, so the
  two branches fork and every later release pull request lists all of `dev`'s history again. A merge
  commit puts `dev`'s own commits on `main`, so the next release lists only what is new and no
  merge-back into `dev` is needed.
- Never push to `main`, never open a pull request into `main` from any branch but `dev`, never rebase
  or force-push `dev` or `main`. The `protect-main` and `protect-dev` rulesets block force pushes and
  deletion.
- A pull request into `dev` carries one logical change, conventional commits, and the measurements
  `.claude/rules/performance.md` asks for. Rebase-merge it so `dev` stays linear.

## Experiments
- `experiments/<topic>` branches hold measurement suites, model conversion labs and research notes.
  They branch from `main`, carry their own tooling and environments, and are never merged into `dev`
  or `main`; they are pushed and kept as long as their results matter.
- Nothing under `orukeet-coreml/` exists on `dev` or `main`. Model weights, corpora, exports and build
  output stay out of git on every branch.
- A finding that should change the app arrives as an ordinary `dev` pull request that carries only
  app code and docs and links to the experiment branch that measured it.
- Current experiment branches: `experiments/orukeet-coreML` (the June conversion suite) and
  `feat/orukeet-coreml-lab` (the September lab, named before this rule; new ones take the
  `experiments/` prefix).
