# Orukeet Core ML lab

Build Orukeet Core ML variants from the published `.nemo`, then measure them against the greedy
bundle TapTalk ships: word error rate on a sealed 128-clip FLEURS corpus, latency per component.
Everything comes from pinned public sources, so the results reproduce on any Apple Silicon Mac.

## Read in this order

1. [docs/setup.md](docs/setup.md): requirements, one-time downloads, environments.
2. [docs/bench.md](docs/bench.md): the regression corpus, how a bundle is scored, how parity with
   the published numbers was checked.
3. [docs/bundles.md](docs/bundles.md): exporting the model and building the encoder variants.
4. [docs/profiling.md](docs/profiling.md): latency tools, what each number means.
5. [docs/batched-joint.md](docs/batched-joint.md): the K-frame joint experiment.
6. [docs/results.md](docs/results.md): the measured tables.
7. [docs/findings.md](docs/findings.md): what the measurements taught us.
8. [docs/research.md](docs/research.md): the ideas that were considered and where each ended.

## Quickstart

```bash
make setup                      # converter source, two uv environments
make nemo shipped vendor corpus # checkpoint, shipped bundle, Nathan's tooling, sealed corpus
make export bundles             # FP16 export, int8 and FP16 bundles
make reg-all score              # transcribe every bundle on the corpus, score
make profile AUDIO=data/fixtures/jfk.wav
```

`make help` lists every target. Generated files stay out of git: `vendor/`, `work/`, `models/`,
`data/`, `out/`, `reports/_raw/`.

## Layout

```
Makefile            every entry point
convert/            export, quantize, prune, assemble, batched joint, audit
bench/              corpus sealing, scoring
swift/              ttprof (latency), ttreg (corpus runner), ttdecode (own decode loop)
docs/               the guides above
reports/            scores and audits kept in git
```
