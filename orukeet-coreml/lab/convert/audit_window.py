#!/usr/bin/env python3
# Parity audit: compares encoder output frames between the full 15 s window and a shorter fixed
# window, on the frames both windows agree are valid. A shorter window traces a smaller encoder
# graph; this checks the frames it still computes stay numerically close to the 15 s baseline.
import argparse
import json
import math
import os
from pathlib import Path

import coremltools as ct
import numpy as np
import soundfile as sf

SAMPLE_RATE = 16000
FULL_WINDOW_SAMPLES = 240000
# 80 ms encoder frame: 8x subsampling of a 10 ms mel hop, both at 16 kHz.
FRAME_SAMPLES = 1280


def declared_length(num_samples: int, window_samples: int) -> int:
    aligned = math.ceil(num_samples / FRAME_SAMPLES) * FRAME_SAMPLES
    return min(window_samples, aligned)


def load(path: Path) -> ct.models.MLModel:
    return ct.models.MLModel(str(path), compute_units=ct.ComputeUnit.CPU_ONLY)


def relative(path: Path) -> str:
    # Record paths relative to the working directory in the report: absolute paths are
    # machine-specific and the report is committed alongside the reports/ directory.
    return os.path.relpath(str(path), os.getcwd())


def run_window(preprocessor: ct.models.MLModel, encoder: ct.models.MLModel, audio: np.ndarray, window_samples: int):
    n = audio.shape[0]
    length = declared_length(n, window_samples)
    padded = np.zeros((1, window_samples), dtype=np.float32)
    padded[0, :n] = audio
    mel = preprocessor.predict({"audio_signal": padded, "audio_length": np.array([length], dtype=np.int32)})
    encoded = encoder.predict({"mel": mel["mel"], "mel_length": mel["mel_length"]})
    return encoded["encoder"], int(encoded["encoder_length"].item())


def audit_clip(path: Path, window_seconds: float, full_pre, full_enc, win_pre, win_enc) -> dict:
    audio, rate = sf.read(str(path), dtype="float32")
    if audio.ndim > 1:
        audio = audio[:, 0]
    if rate != SAMPLE_RATE:
        raise SystemExit(f"expected {SAMPLE_RATE} Hz mono audio: {path} is {rate} Hz")
    window_samples = int(round(window_seconds * SAMPLE_RATE))
    if audio.shape[0] > window_samples:
        raise SystemExit(f"{path}: {audio.shape[0]} samples exceeds the {window_samples}-sample window")
    if audio.shape[0] > FULL_WINDOW_SAMPLES:
        raise SystemExit(f"{path}: {audio.shape[0]} samples exceeds the 15 s window")

    full_encoder, full_length = run_window(full_pre, full_enc, audio, FULL_WINDOW_SAMPLES)
    window_encoder, window_length = run_window(win_pre, win_enc, audio, window_samples)

    common = min(full_length, window_length)
    full_slice = full_encoder[0, :, :common]
    window_slice = window_encoder[0, :, :common]
    diff = np.abs(full_slice - window_slice)
    full_argmax = np.argmax(full_slice, axis=0)
    window_argmax = np.argmax(window_slice, axis=0)
    agreement = float(np.mean(full_argmax == window_argmax)) if common > 0 else 0.0

    return {
        "audio": path.name,
        "input_samples": int(audio.shape[0]),
        "input_seconds": round(audio.shape[0] / SAMPLE_RATE, 3),
        "full_encoder_length": full_length,
        "window_encoder_length": window_length,
        "common_frames": int(common),
        "max_abs_diff": float(diff.max()) if common > 0 else 0.0,
        "mean_abs_diff": float(diff.mean()) if common > 0 else 0.0,
        "argmax_agreement": agreement,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--full-preprocessor", type=Path, required=True)
    ap.add_argument("--full-encoder", type=Path, required=True)
    ap.add_argument("--window-preprocessor", type=Path, required=True)
    ap.add_argument("--window-encoder", type=Path, required=True)
    ap.add_argument("--audio", type=Path, nargs="+", required=True, help="16 kHz mono wav clips")
    ap.add_argument("--window-seconds", type=float, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    full_pre = load(args.full_preprocessor)
    full_enc = load(args.full_encoder)
    win_pre = load(args.window_preprocessor)
    win_enc = load(args.window_encoder)

    results = []
    for path in args.audio:
        result = audit_clip(path, args.window_seconds, full_pre, full_enc, win_pre, win_enc)
        results.append(result)
        print(
            f"{result['audio']}: {result['input_seconds']}s common={result['common_frames']} frames "
            f"(full={result['full_encoder_length']}, window={result['window_encoder_length']}) "
            f"max_abs_diff={result['max_abs_diff']:.4f} mean_abs_diff={result['mean_abs_diff']:.5f} "
            f"argmax_agreement={result['argmax_agreement']:.4f}"
        )

    report = {
        "window_seconds": args.window_seconds,
        "full_preprocessor": relative(args.full_preprocessor),
        "full_encoder": relative(args.full_encoder),
        "window_preprocessor": relative(args.window_preprocessor),
        "window_encoder": relative(args.window_encoder),
        "clips": results,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
