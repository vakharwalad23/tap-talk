#!/usr/bin/env python3
# Download FLEURS test clips and emit 16 kHz mono wavs plus a manifest for the Swift harness.
# Files are pulled directly from the google/fleurs dataset repo to avoid the datasets loader script.
import argparse
import json
import tarfile
from pathlib import Path

import soundfile as sf
import librosa
from huggingface_hub import hf_hub_download

REPO = "google/fleurs"
SR = 16000


def load_tsv(path: Path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        cols = line.split("\t")
        if len(cols) < 3:
            continue
        rows.append((cols[1], cols[2]))
    return rows


def prep_lang(lang: str, split: str, limit: int, out: Path) -> list:
    tsv = Path(hf_hub_download(REPO, f"data/{lang}/{split}.tsv", repo_type="dataset"))
    tar = Path(hf_hub_download(REPO, f"data/{lang}/audio/{split}.tar.gz", repo_type="dataset"))
    audio_root = out / lang / "src"
    audio_root.mkdir(parents=True, exist_ok=True)
    with tarfile.open(tar) as tf:
        tf.extractall(audio_root)

    found = {p.name: p for p in audio_root.rglob("*.wav")}
    wav_dir = out / lang / "wav"
    wav_dir.mkdir(parents=True, exist_ok=True)

    rows = load_tsv(tsv)
    total = len(rows)
    entries = []
    for file_name, ref in rows:
        if len(entries) >= limit:
            break
        src = found.get(file_name)
        if src is None:
            continue
        audio, sr = sf.read(src)
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        if sr != SR:
            audio = librosa.resample(audio, orig_sr=sr, target_sr=SR)
        dst = wav_dir / file_name
        sf.write(dst, audio, SR, subtype="PCM_16")
        entries.append({"audio": str(dst.resolve()), "ref": ref, "lang": lang})

    if total > len(entries):
        print(f"{lang}: using {len(entries)} of {total} clips (limit {limit})")
    return entries


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--langs", default="en_us", help="comma separated FLEURS codes, e.g. en_us,de_de")
    ap.add_argument("--limit", type=int, default=100, help="max clips per language")
    ap.add_argument("--split", default="test")
    ap.add_argument("--out", type=Path, default=Path("fleurs"))
    args = ap.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    manifest = args.out / "manifest.jsonl"
    with manifest.open("w", encoding="utf-8") as f:
        for lang in [x.strip() for x in args.langs.split(",") if x.strip()]:
            for entry in prep_lang(lang, args.split, args.limit, args.out):
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    print(f"manifest: {manifest.resolve()}")


if __name__ == "__main__":
    main()
