#!/usr/bin/env python3
# Compare our measured WER and CER against the Orukeet paper (arXiv 2609.10054, Table 1).
# Paper values are public facts embedded here; our values are parsed from score.py summaries.
import argparse
import re
from pathlib import Path

# Benchmark -> (parakeet WER, parakeet CER, orukeet WER, orukeet CER) from the paper.
PAPER = {
    "LibriSpeech test-clean": (1.53, 0.59, 1.46, 0.56),
    "LibriSpeech test-other": (3.14, 1.32, 2.86, 1.19),
    "Bulgarian": (11.92, 3.84, 10.37, 3.34), "Croatian": (11.29, 3.53, 10.20, 3.67),
    "Czech": (11.12, 3.21, 8.97, 2.67), "Danish": (17.19, 6.31, 14.88, 5.31),
    "Dutch": (6.40, 2.28, 5.60, 1.93), "English": (4.28, 2.00, 3.82, 1.77),
    "Estonian": (13.32, 3.86, 10.44, 3.39), "Finnish": (11.14, 2.59, 9.35, 2.16),
    "French": (4.69, 1.68, 5.01, 1.70), "German": (4.21, 1.41, 3.92, 1.52),
    "Greek": (21.07, 9.01, 30.81, 9.18), "Hungarian": (13.60, 4.20, 10.68, 2.97),
    "Italian": (2.43, 0.79, 2.09, 0.76), "Latvian": (21.78, 5.43, 17.41, 4.21),
    "Lithuanian": (20.95, 5.56, 16.55, 4.27), "Maltese": (19.22, 6.19, 15.60, 5.08),
    "Polish": (6.81, 2.09, 6.11, 1.95), "Portuguese": (4.49, 1.98, 3.73, 1.63),
    "Romanian": (11.44, 3.86, 9.34, 3.07), "Russian": (4.89, 1.49, 4.72, 1.48),
    "Slovak": (9.21, 2.91, 7.75, 2.41), "Slovenian": (22.62, 7.70, 22.11, 8.28),
    "Spanish": (3.22, 1.28, 2.75, 1.04), "Swedish": (13.38, 4.26, 11.36, 3.45),
    "Ukrainian": (6.00, 1.74, 5.39, 1.60),
    "FLEURS pooled": (11.01, 3.57, 9.85, 3.13),
    "FLEURS language macro": (11.07, 3.57, 9.96, 3.15),
}
# Our summary rows use "Pooled"/"Language macro"; map them to the paper's FLEURS labels.
ALIAS = {"Pooled": "FLEURS pooled", "Language macro": "FLEURS language macro"}
ROW = re.compile(r"^\|\s*([^|]+?)\s*\|\s*\d+\s*\|\s*([\d.]+)%\s*\|\s*([\d.]+)%\s*\|"
                 r"\s*([\d.]+)%\s*\|\s*([\d.]+)%\s*\|")


def parse(summary: Path):
    out = {}
    for line in summary.read_text().splitlines():
        m = ROW.match(line)
        if not m:
            continue
        name = m.group(1).strip()
        out[name] = tuple(float(m.group(i)) for i in range(2, 6))
    return out


def rows(ours, fleurs):
    lines = []
    agree = 0
    total = 0
    for name, (pw, pc, ow, oc) in ours.items():
        key = ALIAS.get(name, name) if fleurs else name
        if key not in PAPER:
            continue
        ppw, ppc, pow_, poc = PAPER[key]
        ours_d = ow - pw
        paper_d = pow_ - ppw
        same = (ours_d < 0) == (paper_d < 0)
        if key not in ("FLEURS pooled", "FLEURS language macro"):
            total += 1
            agree += same
        lines.append(f"| {key} | {ppw:.2f} | {pow_:.2f} | {paper_d:+.2f} | "
                     f"{pw:.2f} | {ow:.2f} | {ours_d:+.2f} | {'yes' if same else 'NO'} |")
    return lines, agree, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fleurs", type=Path, required=True, help="FLEURS int8 summary.md")
    ap.add_argument("--librispeech", type=Path, required=True, help="LibriSpeech int8 summary.md")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    ls = parse(args.librispeech)
    fl = parse(args.fleurs)
    head = ("| Benchmark | Paper Pkt WER | Paper Ork WER | Paper dWER | "
            "Ours Pkt WER | Ours Ork WER | Ours dWER | Same sign |")
    sep = "|---|---|---|---|---|---|---|---|"
    ls_rows, _, _ = rows(ls, fleurs=False)
    fl_rows, agree, total = rows(fl, fleurs=True)

    text = ["# Our results vs the Orukeet paper",
            "",
            "WER and CER in percent. dWER is Orukeet minus Parakeet (negative means Orukeet better).",
            "Our numbers are the int8 reports; the paper decodes full-precision NeMo with its own",
            "text normalization, so absolute WER differs. The comparable signal is the sign and",
            "rough size of dWER.",
            "",
            "## LibriSpeech",
            "", head, sep, *ls_rows, "",
            "## FLEURS",
            "", head, sep, *fl_rows, "",
            f"Direction agreement on FLEURS languages: {agree} of {total}.",
            ""]
    out = "\n".join(text)
    args.out.write_text(out)
    print(out)


if __name__ == "__main__":
    main()
