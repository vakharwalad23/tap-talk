#!/usr/bin/env python3
# Publish the converted Orukeet Core ML bundles to a Hugging Face model repo under CC-BY-SA-4.0.
# The two encoder precisions go to float32/ and int8/; LICENSE, NOTICE.md, and the model card go to
# the repo root. Dry run by default; pass --push to actually upload (requires HF auth).
import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REQUIRED = ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
            "JointDecisionv3.mlmodelc", "config.json", "parakeet_vocab.json",
            "parakeet_v3_vocab.json"]


def check_bundle(path: Path, label: str):
    if not path.is_dir():
        sys.exit(f"{label} bundle not found: {path}")
    missing = [f for f in REQUIRED if not (path / f).exists()]
    if missing:
        sys.exit(f"{label} bundle incomplete, missing: {missing}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="target repo id, e.g. yourname/orukeet-coreml")
    ap.add_argument("--fp32", type=Path, required=True, help="float32 bundle directory")
    ap.add_argument("--int8", type=Path, required=True, help="int8 bundle directory")
    ap.add_argument("--private", action="store_true", help="create the repo as private")
    ap.add_argument("--push", action="store_true", help="actually upload (default is a dry run)")
    args = ap.parse_args()

    check_bundle(args.fp32, "float32")
    check_bundle(args.int8, "int8")
    for f in ("LICENSE", "NOTICE.md", "MODEL_CARD.md"):
        if not (HERE / f).exists():
            sys.exit(f"missing publish file: {HERE / f}")

    plan = [
        f"repo:   {args.repo} ({'private' if args.private else 'public'})",
        f"float32/  <- {args.fp32}",
        f"int8/     <- {args.int8}",
        f"README.md <- {HERE / 'MODEL_CARD.md'}",
        f"LICENSE   <- {HERE / 'LICENSE'}",
        f"NOTICE.md <- {HERE / 'NOTICE.md'}",
    ]
    print("\n".join(plan))
    if not args.push:
        print("\ndry run; pass --push to upload (needs huggingface-cli login or HF_TOKEN)")
        return

    from huggingface_hub import HfApi
    api = HfApi()
    api.create_repo(args.repo, repo_type="model", private=args.private, exist_ok=True)
    api.upload_folder(repo_id=args.repo, folder_path=str(args.fp32), path_in_repo="float32")
    api.upload_folder(repo_id=args.repo, folder_path=str(args.int8), path_in_repo="int8")
    api.upload_file(repo_id=args.repo, path_in_repo="README.md",
                    path_or_fileobj=str(HERE / "MODEL_CARD.md"))
    api.upload_file(repo_id=args.repo, path_in_repo="LICENSE", path_or_fileobj=str(HERE / "LICENSE"))
    api.upload_file(repo_id=args.repo, path_in_repo="NOTICE.md",
                    path_or_fileobj=str(HERE / "NOTICE.md"))
    print(f"\npushed to https://huggingface.co/{args.repo}")


if __name__ == "__main__":
    main()
