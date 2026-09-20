# Branching Standards

## Flow
- `dev` is the integration branch and the repository's default branch. Every change lands on `dev`
  through a pull request from a `<type>/<what-it-does>` branch.
- `main` is release-only. The only thing that reaches `main` is `dev`, moved by the maintainer through
  a pull request from `dev`. Branch protection requires that pull request, the `head-is-dev` check and
  the `no-experiment-paths` check, and applies to administrators too.
- Never push to `main`, never open a pull request into `main` from any branch but `dev`, never rebase
  or force-push `dev` or `main`.
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
