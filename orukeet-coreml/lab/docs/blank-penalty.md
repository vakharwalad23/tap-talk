# Blank penalty

Idea: greedy TDT emits blank whenever the blank logit wins the argmax. Subtracting a penalty from
the blank logit before the argmax trades deletions for insertions, which helps models that delete
too much. The shipped greedy joint exposes only the winner, so the sweep uses the baseline
profile's joint, whose 64-entry top-K outputs let the loop re-pick the best non-blank token when
the penalized blank loses.

## Run

```bash
make shipped-baseline                          # models/shipped-baseline/, the joint with top-K outputs
make sweep PENALTIES="0.5 1.0 1.5 2.0 3.0"     # reports/_raw/penalty-<p>-{a,b}.json
make score
```

`ttdecode --blank-penalty X` applies the penalty only when the argmax is blank: if the best
non-blank logit in the top-K list beats the blank logit minus X, that token is emitted with the
frame's duration bin, and its confidence becomes the softmax over the top-K logits. Penalty 0 with
the baseline joint reproduces the greedy transcripts exactly (0 of 128 differ), so the sweep
measures the penalty alone.

## Results, 128 clips

| Penalty | Errors / words | WER |
|---|---|---|
| 0 (greedy) | 194 / 2538 | 7.64 |
| 0.5 | 194 / 2538 | 7.64 |
| 1.0 | 199 / 2538 | 7.84 |
| 1.5 | 200 / 2538 | 7.88 |
| 2.0 | 201 / 2538 | 7.92 |
| 3.0 | 208 / 2538 | 8.20 |

## Verdict

No gain. 0.5 ties and every larger value adds errors: the model does not under-emit on this
corpus, so the penalty only buys insertions. Closed. Phrase boosting and n-gram fusion, the other
decode-side ideas, use the same top-K outputs and still need a vocabulary test set before they can
be measured.
