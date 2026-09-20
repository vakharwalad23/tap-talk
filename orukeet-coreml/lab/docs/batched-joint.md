# Batched joint

Idea: the single-step joint scores one encoder frame per Core ML call. A graph that scores K frames
against the same decoder projection would cut the number of calls during blank runs.

## Build

```bash
make joint-batched K=8    # out/joint/JointDecisionBatchedK8.mlmodelc (+ .mlpackage, receipt json)
make joint-batched K=16
```

`convert/export_batched_joint.py` loads the `.nemo`, wraps the joint with an `encoder_steps
[1, 1024, K]` input, and adds two outputs per frame next to token, probability and duration: the
blank logit and the log-sum-exp of the token logits. Those two make blank penalties, phrase boosting
and language-model fusion possible later without the 8193 logits. The log-sum-exp subtracts the
maximum explicitly; the fused op overflows in FP16.

## Audit

```bash
make audit K=8            # reports/audit-k8.json
```

`convert/audit_batched_joint.py` walks the shipped single-step greedy decode over the four fixture
clips and, at every visited frame, scores the same frames through the batched joint with the same
decoder projection, on CPU and with the Neural Engine allowed. Result: token and duration argmax
agree on 99.2 to 100 percent of frame decisions, probabilities within 0.05.

## Measure

```bash
make decode AUDIO=data/fixtures/jfk.wav JOINT=out/joint/JointDecisionBatchedK8.mlmodelc
```

## Verdict

Slower. TDT durations already skip the blank frames, so the single-step joint is called about once
per emitted token (46 calls for 38 tokens on the 11 s clip), and every emitted token changes the
decoder projection, which invalidates the rest of a batch. A K=8 call costs 0.61 ms against 0.17 ms
for one frame; decode time went from 20 ms to 36 ms (K=16: 48 ms). The graphs and the audit stay for
reference; the idea is closed.
