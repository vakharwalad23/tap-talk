# Branching

How changes move through this repository, and which branches never meet.

## Branches

| Branch | Purpose | Who writes to it |
|---|---|---|
| `main` | Release history and the default branch. Every commit is a state that was shipped or is ready to ship. | Only the maintainer, only by merging a pull request from `dev` with a merge commit. |
| `dev` | Integration. Pull requests target it (pick `dev` as the base; the default is `main`). | Anyone, through a pull request from a feature branch. |
| `<type>/<what-it-does>` | One change: `feat/live-typing-eou`, `fix/paste-race`, `build/fluidaudio-0.15.8`. Branch from `dev`. | Its author. |
| `experiments/<topic>` | Measurement suites, conversion labs, research notes. Branch from `main`. | Its author. Never merged anywhere. |

## Flow

```
feature branch --pull request--> dev --pull request by the maintainer--> main
experiments/<topic>  (from main; kept, pushed, never merged)
```

1. Branch from `dev`, commit with conventional commits (`.claude/rules/commits.md`), keep every file
   ASCII (`.claude/rules/ascii.md`).
2. Open a pull request against `dev`. It carries one logical change and the before and after
   measurements the performance standard asks for.
3. Rebase-merge into `dev` so its history stays linear.
4. The maintainer opens a pull request from `dev` into `main` when `dev` is a release candidate, and
   merges it with "Create a merge commit" once the checks pass.

Squash and rebase are not allowed into `main`. Both write copies of `dev`'s commits, so `main` never
contains `dev`'s own commits and every later release pull request lists the whole history again. A
merge commit keeps `dev`'s commits on `main`, so each release lists only what changed since the last
one, and `dev` needs no merge-back afterwards.

## What protects main

Branch protection on `main` and the `protect-main` ruleset, enforced for administrators as well:

- a pull request is required; nothing is pushed to `main` directly, no force pushes, no deletion;
- merge commits only; squash and rebase merges are disabled;
- `dev` does not have to be up to date with `main` before merging, since the only commits `main` has
  that `dev` lacks are release merge commits;
- the `head-is-dev` check fails any pull request into `main` whose source branch is not `dev`;
- the `no-experiment-paths` check fails any pull request into `dev` or `main` that touches
  `orukeet-coreml/`;
- review conversations must be resolved before merging.

Both checks live in `.github/workflows/branch-policy.yml`. The `protect-dev` ruleset blocks force
pushes to `dev` and its deletion, including the "Delete branch" button after a release merge.

## Experiments

Experiment branches exist so measurement code, converted models and research notes never enter the
app's history. `orukeet-coreml/` lives only there. Rules:

- branch from `main` as `experiments/<topic>`, push it, keep it;
- keep weights, corpora, exports and build products out of git on the experiment branch too;
- when a result should change the app, open a normal `dev` pull request with app code and docs only,
  and link the experiment branch that measured it.

Existing experiment branches: `experiments/orukeet-coreML` (June 2026 Core ML conversion suite and
FLEURS benchmark) and `feat/orukeet-coreml-lab` (September 2026 lab: int8 encoder, decode loop,
shorter windows, placement tools; named before this policy).
