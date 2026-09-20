#!/usr/bin/env python3
# Parity audit: walk the shipped single-step greedy decode over real recordings and, at every
# visited frame, score the same frames through the batched joint with the same decoder projection.
# Reports argmax agreement for token and duration and the largest probability deviation.
import argparse
import json
from pathlib import Path

import coremltools as ct
import numpy as np
import soundfile as sf

BLANK = 8192
WINDOW = 240000


def load(directory: Path, name: str, units):
    return ct.models.CompiledMLModel(str(directory / f"{name}.mlmodelc"), compute_units=units)


def audit(bundle: Path, batched: Path, k: int, fixtures, units):
    pre = load(bundle, "Preprocessor", ct.ComputeUnit.CPU_ONLY)
    enc = load(bundle, "Encoder", units)
    dec = load(bundle, "Decoder", ct.ComputeUnit.CPU_ONLY)
    single = load(bundle, "JointDecisionv3", ct.ComputeUnit.CPU_ONLY)
    batch = ct.models.CompiledMLModel(str(batched), compute_units=units)
    report = []
    for path in fixtures:
        audio, rate = sf.read(path, dtype="float32")
        if audio.ndim != 1 or rate != 16000 or not 0 < len(audio) <= WINDOW:
            raise SystemExit(f"expected 16 kHz mono audio up to 15 s: {path}")
        padded = np.pad(audio, (0, WINDOW - len(audio)))[None]
        mel = pre.predict({"audio_signal": padded, "audio_length": np.array([len(audio)], np.int32)})
        encoded = enc.predict(mel)
        frames = int(encoded["encoder_length"].item())
        encoder = encoded["encoder"]  # [1, 1024, 188]
        h = np.zeros((2, 1, 640), np.float32)
        c = h.copy()
        target = BLANK
        compared = agree_token = agree_duration = 0
        max_prob_diff = 0.0
        max_lse_err = 0.0
        t = 0
        emitted = 0
        while t < frames:
            prediction = dec.predict({"targets": np.array([[target]], np.int32), "target_length": np.array([1], np.int32),
                                      "h_in": h, "c_in": c})
            dec_step = prediction["decoder"]
            end = min(t + k, frames)
            block = np.zeros((1, 1024, k), np.float32)
            block[:, :, : end - t] = encoder[:, :, t:end]
            out = batch.predict({"encoder_steps": block, "decoder_step": dec_step})
            for i in range(end - t):
                ref = single.predict({"encoder_step": encoder[:, :, t + i : t + i + 1].copy(), "decoder_step": dec_step})
                compared += 1
                agree_token += int(ref["token_id"].item()) == int(out["token_id"][0, i, 0])
                agree_duration += int(ref["duration"].item()) == int(out["duration"][0, i, 0])
                max_prob_diff = max(max_prob_diff, abs(float(ref["token_prob"].item()) - float(out["token_prob"][0, i, 0])))
                # blank_logit - logsumexp must equal log p(blank); check it against the reference
                # token_prob when the reference argmax is blank.
                if int(ref["token_id"].item()) == BLANK:
                    lp = float(out["blank_logit"][0, i, 0] - out["logsumexp"][0, i, 0])
                    max_lse_err = max(max_lse_err, abs(np.exp(lp) - float(ref["token_prob"].item())))
            # Advance the reference greedy walk from the single-step decision at frame t.
            ref0 = single.predict({"encoder_step": encoder[:, :, t : t + 1].copy(), "decoder_step": dec_step})
            token = int(ref0["token_id"].item())
            duration = int(ref0["duration"].item())
            if token != BLANK:
                emitted += 1
                target, h, c = token, prediction["h_out"], prediction["c_out"]
                if duration == 0:
                    duration = 1
            else:
                duration = max(duration, 1)
            t += duration
        report.append({"audio": Path(path).name, "frames": frames, "emitted_tokens": emitted, "compared": compared,
                       "token_agreement": agree_token / max(compared, 1), "duration_agreement": agree_duration / max(compared, 1),
                       "max_token_prob_diff": max_prob_diff, "max_blank_prob_err": max_lse_err})
        print(json.dumps(report[-1]))
    return report


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle", type=Path, required=True, help="shipped compiled bundle (single-step joint)")
    ap.add_argument("--batched", type=Path, required=True, help="JointDecisionBatchedK*.mlmodelc")
    ap.add_argument("--k", type=int, required=True)
    ap.add_argument("--fixtures", type=Path, required=True, help="directory of 16 kHz mono wav files")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    fixtures = sorted(str(p) for p in args.fixtures.glob("*.wav"))
    if not fixtures:
        raise SystemExit(f"no wav files in {args.fixtures}")
    result = {"k": args.k, "units": {}}
    for units in (ct.ComputeUnit.CPU_ONLY, ct.ComputeUnit.CPU_AND_NE):
        result["units"][units.name] = audit(args.bundle, args.batched, args.k, fixtures, units)
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
