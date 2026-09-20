# Regression bench

Word error rate on the same 128 clips Nathan scored in Oruk-AI/orukeet#6, with his scorer, so every
number here is comparable to his tables.

## Corpus

Two samples of 64 FLEURS test clips, 8 per language (en, fr, es, lv, de, it, uk, ru), each under
15 s. Nathan's `prepare_fleurs.py` selects them deterministically from the pinned dataset revision:
the first 8 eligible files per language, then the next 8. `make corpus` runs that script and checks
every file's sha256 against his published manifests.

```
data/fleurs-a/   first sample, manifest.json + 64 wav
data/fleurs-b/   second sample
```

## Run a bundle

```bash
make reg DIR=models/shipped-greedy LABEL=shipped-greedy
make reg DIR=out/bundles/orukeet-int8sym-greedy LABEL=orukeet-int8sym-greedy
make reg-all            # shipped bundle plus everything under out/bundles/
```

`ttreg` loads the four `.mlmodelc` files of `DIR` through FluidAudio 0.15.5 (the version TapTalk
pins), transcribes each clip from a fresh decoder state, and writes
`reports/_raw/<LABEL>-a.json` and `<LABEL>-b.json`: path, sha256, language, text, milliseconds.

## Score

```bash
make score
```

`bench/score.py` scores every `reports/_raw/*-{a,b}.json` and Nathan's published hypotheses
(`nathan/greedy`, `nathan/baseline`, `nathan/parakeet`, `nathan/nemo-fp32`) with his
`evaluation/standard_asr/scoring.py`, prints per-language error counts, and writes
`reports/score.md` and `reports/score.json`. Pass `--identical ours=theirs` to list the transcripts
that differ between two labels (default compares `shipped-greedy` with `nathan/greedy`).

## Parity check

Before trusting any new number, the shipped bundle through this bench must reproduce Nathan's
result. It does: 194 errors / 2538 words, identical per language, 127 of 128 transcripts
byte-identical (one Ukrainian comma differs, an FP16 tie).

## Reading the numbers

128 clips and about 2540 words resolve differences of roughly 5 words. Treat anything closer than
that as a tie; the full 20146-clip FLEURS run decides those.
