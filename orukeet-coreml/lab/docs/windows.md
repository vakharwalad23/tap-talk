# Shorter fixed windows

Idea: the 15 s export fixes the encoder's traced shape at 1501 mel frames regardless of how much
of the clip is real audio. A shorter fixed window traces a smaller encoder graph, cutting the
sequence length (and so the attention and convolution work) for short dictation clips. The
preprocessor is exported at the same fixed shape as the window, for the same reason the shipped
15 s bundle avoids the RangeDim preprocessor: a flexible-shape input runs about 8x slower on CPU
(11 ms against 1.4 ms per clip, see docs/bundles.md).

## Build

```bash
make export-window                # SECONDS=5 default, out/export-5s/, about 1 minute
make export-window SECONDS=10     # out/export-10s/, about 1 minute
```

`convert/export_window.sh` copies the vendored `convert-parakeet.py` to a sibling
`convert-parakeet-window.py` inside the same vendored directory (so its local imports keep
working) and patches the copy: the trace window becomes `float(os.environ["WINDOW_SECONDS"])`
instead of the hardcoded `15.0`, and the preprocessor's `ct.RangeDim(1, max_samples)` input becomes
the fixed `(1, max_samples)`. Both patches are grep-verified before the export runs. The vendored
original is never edited; the generated copy lives under `vendor/` and is not committed. Weights
and precision (FP16 mlprogram) are unchanged from the 15 s export, so the encoder `.mlpackage` stays
about the same size on disk (the learned weights do not shrink; only the traced sequence length
does) - `make export` gives 1.1 GB, and so does each window.

## Shapes

Measured from each export's `metadata.json` and confirmed with coremltools against the mlpackage
spec. Input/output names are unchanged across windows: preprocessor `audio_signal`/`audio_length`
in, `mel`/`mel_length` out; encoder `mel`/`mel_length` in, `encoder`/`encoder_length` out.

| Window | Samples | Mel | Encoder |
|---|---|---|---|
| 15 s (`make export`, baseline) | 240000 | [1, 128, 1501] | [1, 1024, 188] |
| 10 s (`make export-window SECONDS=10`) | 160000 | [1, 128, 1001] | [1, 1024, 126] |
| 5 s (`make export-window SECONDS=5`) | 80000 | [1, 128, 501] | [1, 1024, 63] |

## Audit

```bash
make audit-window                                                              # 5 s, reports/audit-window-5s.json
make audit-window SECONDS=10 WINDOW_AUDIO="data/fleurs-a/en_us-10197164397713068203.wav data/fleurs-b/lv_lv-10382133161810297551.wav"
```

`convert/audit_window.py` feeds the same clip through the shipped fixed 15 s preprocessor + the lab
FP16 15 s encoder (the full-window side) and through a window export's own preprocessor + encoder
(the window side), padding each to its own window and declaring a frame-aligned valid length
(`min(window_samples, ceil(n / 1280) * 1280)`, matching the app). It compares the two encoder
outputs on the frames both sides agree are valid: max and mean absolute difference over the 1024
channels, and the fraction of those frames whose channel-wise argmax agrees. `WINDOW_AUDIO` picks
the clips; the default is the two shortest clips in the sealed corpus. The sealed corpus has only
one clip at or under 4.5 s (4.32 s), so the second 5 s clip is the next shortest available (4.80 s),
still safely under the 80000-sample window.

## Results

| Window | Clip | Duration | Common frames | Max abs diff | Mean abs diff | Argmax agreement |
|---|---|---|---|---|---|---|
| 5 s | en_us-10233995782544396174 (fleurs-a) | 4.32 s | 55 | 0.0752 | 0.00119 | 0.8909 |
| 5 s | en_us-1038214857203833067 (fleurs-b) | 4.80 s | 61 | 0.0884 | 0.00165 | 0.9016 |
| 10 s | en_us-10197164397713068203 (fleurs-a) | 5.76 s | 73 | 0.0027 | 0.00017 | 0.9726 |
| 10 s | lv_lv-10382133161810297551 (fleurs-b) | 9.36 s | 118 | 0.0114 | 0.00025 | 1.0000 |

Full and window sides always agreed on `encoder_length` (no truncation on either side for these
clips). The 5 s window disagrees with the 15 s baseline on 10 to 15 percent of per-frame channel
argmax, well above the 10 s window's 0 to 3 percent; absolute feature differences follow the same
pattern (max diff one order of magnitude larger at 5 s). Two effects are folded together here and
not separated: the window-size change itself, and the full-window side using the shipped
preprocessor while the window side uses the lab's own preprocessor export, which bundles.md already
notes "produces slightly different features" than the shipped one at matched precision. A shorter
clip is a much larger fraction of a 5 s window than of the 15 s window, so any boundary or
normalization difference between the two preprocessor implementations has more room to show up in
the 5 s case. Channel-wise argmax over 1024 raw encoder features is also a far more sensitive
metric than the batched-joint audit's decision-head token argmax (docs/batched-joint.md); it is not
a decoding accuracy number by itself.

## Verdict

Not yet decided. Shapes trace and export cleanly at both windows with no converter changes beyond
the two documented patches, and the audited encoder features stay close to the 15 s baseline at
10 s, less so at 5 s. Whether either window is worth shipping depends on latency, not measured
here: `make decode AUDIO=<clip> DIR=<a bundle built from one of these exports>` with `ttdecode`
gives the key-up-to-paste number the performance standard requires before any verdict.
