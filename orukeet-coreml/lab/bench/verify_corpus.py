#!/usr/bin/env python3
# A sealed corpus is only comparable if every fixture is byte-identical to the published one.
import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, required=True, help="our manifest.json")
    ap.add_argument("--expected", type=Path, required=True, help="Nathan's corpus.json")
    args = ap.parse_args()
    ours = json.loads(args.corpus.read_text())["fixtures"]
    theirs = json.loads(args.expected.read_text())["fixtures"]
    expected = {row["sha256"]: row for row in theirs}
    problems = []
    for row in ours:
        path = args.corpus.parent / row["path"]
        digest = sha256(path)
        if digest != row["sha256"]:
            problems.append(f"{row['path']}: file hash {digest[:12]} differs from its manifest")
        if digest not in expected:
            problems.append(f"{row['path']}: not in the published corpus")
    if len(ours) != len(theirs):
        problems.append(f"{len(ours)} fixtures here vs {len(theirs)} published")
    if problems:
        raise SystemExit("\n".join(problems))
    print(f"{args.corpus}: {len(ours)} fixtures match {args.expected.name}")


if __name__ == "__main__":
    main()
