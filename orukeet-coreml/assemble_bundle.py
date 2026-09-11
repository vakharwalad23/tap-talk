#!/usr/bin/env python3
# Map compiled mlmodelc into the FluidAudio bundle layout and verify the tokenizer.
import argparse
import json
import re
import shutil
import sys
import tarfile
import tempfile
from pathlib import Path

# Canonical FluidAudio name to stem substrings that identify each compiled component.
TARGETS = {
    "Preprocessor": ("preprocessor",),
    "Encoder": ("encoder",),
    "Decoder": ("decoder",),
    # FluidAudio's v3 joint is the single-step graph with top-K outputs, not the full-window one.
    "JointDecisionv3": ("jointdecisionsinglestep",),
}
# Variant stems that must never fill the canonical four.
EXCLUDE = ("mel", "v2", "v3", "int4", "int8", "quant", "fused", "rnnt", "melspectrogram")
# Non-model files copied verbatim from the reference bundle; vocab is identical to Parakeet v3.
REF_FILES = ("config.json", "parakeet_vocab.json", "parakeet_v3_vocab.json")


def norm(stem: str) -> str:
    return re.sub(r"[^a-z0-9]", "", stem.lower()).replace("parakeet", "")


def find_component(compiled: Path, name: str, keys) -> Path:
    candidates = []
    for p in sorted(compiled.rglob("*.mlmodelc")):
        n = norm(p.stem)
        if any(k in n for k in keys) and not any(x in n for x in EXCLUDE):
            candidates.append(p)
    if len(candidates) == 1:
        return candidates[0]
    listing = ", ".join(p.name for p in compiled.rglob("*.mlmodelc")) or "(none)"
    if not candidates:
        sys.exit(f"no compiled .mlmodelc matched {name}. Present: {listing}")
    sys.exit(f"ambiguous match for {name}: {[p.name for p in candidates]}. Present: {listing}")


def orukeet_pieces(nemo: Path):
    with tarfile.open(nemo) as tf:
        models = [m for m in tf.getmembers() if m.name.endswith(".model")]
        if not models:
            return None
        pick = next((m for m in models if "token" in m.name.lower()), models[0])
        with tempfile.TemporaryDirectory() as tmp:
            tf.extract(pick, tmp)
            import sentencepiece as spm
            sp = spm.SentencePieceProcessor(model_file=str(Path(tmp) / pick.name))
            return [sp.id_to_piece(i) for i in range(sp.get_piece_size())]


def reference_tokens(path: Path):
    data = json.loads(path.read_text())
    if isinstance(data, list):
        if data and isinstance(data[0], (list, tuple)):
            return [str(x[1]) for x in data]
        return [str(x) for x in data]
    if isinstance(data, dict):
        vals = list(data.values())
        if vals and all(isinstance(v, int) for v in vals):
            return [k for k, _ in sorted(data.items(), key=lambda kv: kv[1])]
        return [data[k] for k in sorted(data, key=lambda k: int(k))]
    return None


def verify_vocab(nemo: Path, ref_vocab: Path) -> bool:
    pieces = orukeet_pieces(nemo)
    if pieces is not None:
        # SentencePiece marks a leading space as U+2581; the vocab json uses a literal space.
        pieces = [p.replace(chr(0x2581), " ") for p in pieces]
    ref = reference_tokens(ref_vocab)
    if pieces is None or ref is None:
        print("WARN: could not extract tokens for comparison; verify the vocab by hand")
        return False
    if len(pieces) != len(ref):
        print(f"WARN: vocab size differs (orukeet {len(pieces)} vs reference {len(ref)})")
        return False
    mism = [i for i, (a, b) in enumerate(zip(pieces, ref)) if a != b]
    if mism:
        print(f"WARN: {len(mism)} token(s) differ, first at id {mism[0]}: "
              f"orukeet={pieces[mism[0]]!r} reference={ref[mism[0]]!r}")
        return False
    print(f"vocab verified identical to Parakeet v3 ({len(pieces)} tokens)")
    return True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiled", type=Path, required=True, help="dir of compiled .mlmodelc")
    ap.add_argument("--reference", type=Path, required=True, help="dir with parakeet_vocab.json")
    ap.add_argument("--nemo", type=Path, required=True, help="orukeet .nemo checkpoint")
    ap.add_argument("--out", type=Path, required=True, help="output bundle dir")
    args = ap.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    for name, keys in TARGETS.items():
        src = find_component(args.compiled, name, keys)
        dst = args.out / f"{name}.mlmodelc"
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        print(f"{name}.mlmodelc  <-  {src.name}")

    ref_vocab = args.reference / "parakeet_vocab.json"
    if not ref_vocab.exists():
        sys.exit(f"reference vocab not found: {ref_vocab}")
    identical = verify_vocab(args.nemo, ref_vocab)
    for name in REF_FILES:
        src = args.reference / name
        if not src.exists():
            sys.exit(f"reference file not found: {src}")
        shutil.copy2(src, args.out / name)
    if not identical:
        print("vocab reused from reference despite the warning above; confirm before shipping")

    missing = [f"{n}.mlmodelc" for n in TARGETS if not (args.out / f"{n}.mlmodelc").exists()]
    missing += [n for n in REF_FILES if not (args.out / n).exists()]
    if missing:
        sys.exit(f"bundle incomplete, missing: {missing}")
    print(f"\nbundle complete: {args.out}")


if __name__ == "__main__":
    main()
