#!/usr/bin/env python3
# Score a benchmark run. Reads results.json (raw ref/hyp/ms per clip), computes corpus and
# median word error rate per language, and writes summary.md. Numbers are normalized to digits
# so a model that says "twenty nine" is not penalized against a reference that writes "29".
import argparse
import json
from pathlib import Path

ORDER = ["parakeet", "orukeet"]
UNITS = {w: i for i, w in enumerate(
    "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen "
    "fifteen sixteen seventeen eighteen nineteen".split())}
TENS = {"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90}
SCALES = {"hundred": 100, "thousand": 1000, "million": 1000000, "billion": 1000000000}


def collapse_numbers(tokens):
    out = []
    i = 0
    while i < len(tokens):
        if tokens[i] not in UNITS and tokens[i] not in TENS and tokens[i] not in SCALES:
            out.append(tokens[i])
            i += 1
            continue
        result = current = used = 0
        while i < len(tokens):
            w = tokens[i]
            if w in UNITS:
                current += UNITS[w]
            elif w in TENS:
                current += TENS[w]
            elif w in SCALES:
                scale = SCALES[w]
                if scale == 100:
                    current = (current or 1) * 100
                else:
                    current = (current or 1) * scale
                    result += current
                    current = 0
            elif (w == "and" and used > 0 and i + 1 < len(tokens)
                  and (tokens[i + 1] in UNITS or tokens[i + 1] in TENS or tokens[i + 1] in SCALES)):
                i += 1
                continue
            else:
                break
            used += 1
            i += 1
        out.append(str(result + current))
    return out


def normalize(text):
    cleaned = "".join(c if c.isalnum() else " " for c in text.lower())
    return collapse_numbers(cleaned.split())


def edits(a, b):
    if not a:
        return len(b)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def median(xs):
    xs = sorted(xs)
    if not xs:
        return 0.0
    mid = len(xs) // 2
    return xs[mid] if len(xs) % 2 else (xs[mid - 1] + xs[mid]) / 2


def demo():
    assert normalize("twenty-nine") == ["29"]
    assert normalize("eight hundred") == ["800"]
    assert normalize("two thousand nineteen") == ["2019"]
    assert normalize("one hundred percent") == ["100", "percent"]
    assert normalize("Boda-Boda taxi") == ["boda", "boda", "taxi"]
    assert edits(["a", "b"], ["a", "c"]) == 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", type=Path, default=Path("results/results.json"))
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()
    demo()

    rows = json.loads(args.results.read_text())
    models = [m for m in ORDER if any(r["model"] == m for r in rows)]
    langs = sorted({r["lang"] for r in rows})
    agg = {}
    latency = {m: [r["ms"] for r in rows if r["model"] == m] for m in models}
    cells = {}
    for r in rows:
        ref = normalize(r["ref"])
        e = edits(ref, normalize(r["hyp"]))
        c = cells.setdefault((r["lang"], r["model"]), {"edits": 0, "ref": 0, "clip": []})
        c["edits"] += e
        c["ref"] += len(ref)
        c["clip"].append(100 * e / len(ref) if ref else 0)

    def corpus(lang, m):
        c = cells.get((lang, m))
        return 100 * c["edits"] / c["ref"] if c and c["ref"] else 0.0

    lines = [f"| Language | Clips | {models[0].title()} WER | {models[1].title()} WER | Delta (pp) |",
             "|---|---|---|---|---|"]
    for lang in langs:
        clips = len(cells[(lang, models[0])]["clip"])
        w0, w1 = corpus(lang, models[0]), corpus(lang, models[1])
        lines.append(f"| {lang} | {clips} | {w0:.2f}% | {w1:.2f}% | {w1 - w0:+.2f} |")

    def overall(m):
        te = sum(cells[(l, m)]["edits"] for l in langs)
        tr = sum(cells[(l, m)]["ref"] for l in langs)
        return 100 * te / tr if tr else 0.0

    def median_clip(m):
        return median([w for l in langs for w in cells[(l, m)]["clip"]])

    total = sum(len(cells[(l, models[0])]["clip"]) for l in langs)
    o0, o1 = overall(models[0]), overall(models[1])
    lines.append(f"| Overall | {total} | {o0:.2f}% | {o1:.2f}% | {o1 - o0:+.2f} |")
    lines.append("")
    lines.append(f"Median clip WER: {models[0]} {median_clip(models[0]):.2f}%, "
                 f"{models[1]} {median_clip(models[1]):.2f}%.")
    # First clip per model pays warm-up and is dropped from the latency figure.
    lines.append(f"Median warm processing time per clip: "
                 f"{models[0]} {median(latency[models[0]][1:]):.1f} ms, "
                 f"{models[1]} {median(latency[models[1]][1:]):.1f} ms.")

    text = "\n".join(lines) + "\n"
    out = args.out or args.results.parent / "summary.md"
    out.write_text(text)
    print(text)


if __name__ == "__main__":
    main()
