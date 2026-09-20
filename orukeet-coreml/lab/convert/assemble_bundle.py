#!/usr/bin/env python3
# Compile four .mlpackage components into the layout TapTalk installs (Preprocessor, Encoder,
# Decoder, JointDecisionv3 .mlmodelc + parakeet_vocab.json) and record per-file hashes.
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

COMPONENTS = ("preprocessor", "encoder", "decoder", "joint")
NAMES = {"preprocessor": "Preprocessor", "encoder": "Encoder", "decoder": "Decoder", "joint": "JointDecisionv3"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 22), b""):
            h.update(block)
    return h.hexdigest()


def compile_package(package: Path, dest: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["xcrun", "coremlcompiler", "compile", str(package), tmp], check=True)
        produced = list(Path(tmp).glob("*.mlmodelc"))
        if len(produced) != 1:
            raise SystemExit(f"expected one .mlmodelc from {package}, got {produced}")
        shutil.move(str(produced[0]), str(dest))


def main() -> None:
    ap = argparse.ArgumentParser()
    for name in COMPONENTS:
        ap.add_argument(f"--{name}", type=Path, required=True, help=f"{NAMES[name]} .mlpackage")
    ap.add_argument("--vocab", type=Path, required=True, help="parakeet_vocab.json (8192 entries)")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    vocab = json.loads(args.vocab.read_text())
    if len(vocab) != 8192:
        raise SystemExit(f"vocabulary has {len(vocab)} entries, expected 8192")
    if args.out.exists():
        shutil.rmtree(args.out)
    args.out.mkdir(parents=True)

    manifest = {"components": {}}
    for name in COMPONENTS:
        package = getattr(args, name)
        dest = args.out / f"{NAMES[name]}.mlmodelc"
        compile_package(package, dest)
        weights = dest / "weights/weight.bin"
        manifest["components"][NAMES[name]] = {
            "source": str(package),
            "weights_bytes": weights.stat().st_size if weights.exists() else 0,
            "weights_sha256": sha256(weights) if weights.exists() else None,
        }
        print(f"{NAMES[name]}.mlmodelc <- {package.name}")
    shutil.copy2(args.vocab, args.out / "parakeet_vocab.json")
    (args.out / "bundle.json").write_text(json.dumps(manifest, indent=2) + "\n")
    total = sum(f.stat().st_size for f in args.out.rglob("*") if f.is_file())
    print(f"bundle {args.out} ({total / 1e6:.0f} MB)")


if __name__ == "__main__":
    main()
