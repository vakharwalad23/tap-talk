#!/usr/bin/env python3
# Download LibriSpeech test-clean and test-other and emit 16 kHz mono wavs plus a manifest in the
# same shape as the FLEURS prep. LibriSpeech is already 16 kHz mono flac, so this only decodes to wav.
import argparse
import json
import tarfile
import urllib.request
from pathlib import Path

import soundfile as sf
import librosa

SPLITS = {"test-clean": "ls-test-clean", "test-other": "ls-test-other"}
MIRRORS = [
    "https://www.openslr.org/resources/12/",
    "https://us.openslr.org/resources/12/",
    "https://openslr.elda.org/resources/12/",
]
SR = 16000


def download(name: str, dst: Path):
    if dst.exists():
        return
    tmp = dst.with_suffix(dst.suffix + ".partial")
    last = None
    for base in MIRRORS:
        try:
            req = urllib.request.Request(base + name, headers={"User-Agent": "orukeet-bench"})
            with urllib.request.urlopen(req, timeout=60) as r, open(tmp, "wb") as f:
                while chunk := r.read(1 << 20):
                    f.write(chunk)
            tmp.rename(dst)
            return
        except Exception as e:
            last = e
            tmp.unlink(missing_ok=True)
    raise SystemExit(f"failed to download {name} from all mirrors: {last}")


def prep_split(split: str, lang: str, root: Path, out: Path) -> list:
    tar = root / f"{split}.tar.gz"
    download(f"{split}.tar.gz", tar)
    extract = root / "extract"
    base = extract / "LibriSpeech" / split
    if not base.exists():
        with tarfile.open(tar) as t:
            t.extractall(extract)

    wav_dir = out / split
    wav_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    for trans in sorted(base.rglob("*.trans.txt")):
        for line in trans.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            uid, text = line.split(" ", 1)
            flac = trans.parent / f"{uid}.flac"
            audio, sr = sf.read(flac)
            if audio.ndim > 1:
                audio = audio.mean(axis=1)
            if sr != SR:
                audio = librosa.resample(audio, orig_sr=sr, target_sr=SR)
            dst = wav_dir / f"{uid}.wav"
            sf.write(dst, audio, SR, subtype="PCM_16")
            entries.append({"audio": str(dst.resolve()), "ref": text, "lang": lang})
    print(f"{split}: {len(entries)} clips")
    return entries


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path("data/librispeech"))
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    manifest = args.out / "manifest.jsonl"
    with manifest.open("w", encoding="utf-8") as f:
        for split, lang in SPLITS.items():
            for entry in prep_split(split, lang, args.out, args.out):
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    print(f"manifest: {manifest.resolve()}")


if __name__ == "__main__":
    main()
