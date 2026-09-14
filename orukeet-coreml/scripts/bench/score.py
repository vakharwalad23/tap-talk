#!/usr/bin/env python3
# Score benchmark runs. Reads one or more results files (raw ref/hyp/ms rows), merges them by
# model, and reports per-language WER and CER plus pooled and language-macro rows, matching the
# Orukeet paper table. Numbers are normalized to digits so a model that says "twenty nine" is not
# penalized against a reference that writes "29".
import argparse
import json
from pathlib import Path

MODEL_ORDER = ["parakeet", "orukeet"]
# Paper table order and display names; unknown codes fall back to the code, sorted last.
LANG_NAMES = [
    ("bg_bg", "Bulgarian"), ("hr_hr", "Croatian"), ("cs_cz", "Czech"), ("da_dk", "Danish"),
    ("nl_nl", "Dutch"), ("en_us", "English"), ("et_ee", "Estonian"), ("fi_fi", "Finnish"),
    ("fr_fr", "French"), ("de_de", "German"), ("el_gr", "Greek"), ("hu_hu", "Hungarian"),
    ("it_it", "Italian"), ("lv_lv", "Latvian"), ("lt_lt", "Lithuanian"), ("mt_mt", "Maltese"),
    ("pl_pl", "Polish"), ("pt_br", "Portuguese"), ("ro_ro", "Romanian"), ("ru_ru", "Russian"),
    ("sk_sk", "Slovak"), ("sl_si", "Slovenian"), ("es_419", "Spanish"), ("sv_se", "Swedish"),
    ("uk_ua", "Ukrainian"),
    ("ls-test-clean", "LibriSpeech test-clean"), ("ls-test-other", "LibriSpeech test-other"),
]
NAME = dict(LANG_NAMES)
LANG_INDEX = {code: i for i, (code, _) in enumerate(LANG_NAMES)}

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
                if SCALES[w] == 100:
                    current = (current or 1) * 100
                else:
                    current = (current or 1) * SCALES[w]
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
    # Trim the common prefix and suffix first; near-identical strings then cost almost nothing,
    # which keeps character-level CER over 20k clips fast.
    if a == b:
        return 0
    n, m = len(a), len(b)
    lo = 0
    while lo < n and lo < m and a[lo] == b[lo]:
        lo += 1
    while n > lo and m > lo and a[n - 1] == b[m - 1]:
        n -= 1
        m -= 1
    a, b = a[lo:n], b[lo:m]
    if not a:
        return len(b)
    if not b:
        return len(a)
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


def lang_key(code):
    return (LANG_INDEX.get(code, len(LANG_NAMES)), code)


def demo():
    assert normalize("twenty-nine") == ["29"]
    assert normalize("eight hundred") == ["800"]
    assert normalize("two thousand nineteen") == ["2019"]
    assert edits(list("cat"), list("cot")) == 1
    assert edits(["a", "b"], ["a", "c"]) == 1


def wer_cer(cell):
    wer = 100 * cell["we"] / cell["wn"] if cell["wn"] else 0.0
    cer = 100 * cell["ce"] / cell["cn"] if cell["cn"] else 0.0
    return wer, cer


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", nargs="+", type=Path, required=True,
                    help="one or more results.json files; rows are merged by their model field")
    ap.add_argument("--only-lang", default=None, help="keep only this FLEURS code (e.g. en_us)")
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()
    demo()

    rows = []
    for path in args.results:
        rows += json.loads(path.read_text())
    if args.only_lang:
        rows = [r for r in rows if r["lang"] == args.only_lang]
    if not rows:
        raise SystemExit("no rows after filtering")

    models = [m for m in MODEL_ORDER if any(r["model"] == m for r in rows)]
    models += sorted({r["model"] for r in rows} - set(models))
    langs = sorted({r["lang"] for r in rows}, key=lang_key)

    cells = {}
    latency = {m: [] for m in models}
    for r in rows:
        ref_w = normalize(r["ref"])
        hyp_w = normalize(r["hyp"])
        ref_c = list(" ".join(ref_w))
        hyp_c = list(" ".join(hyp_w))
        c = cells.setdefault((r["lang"], r["model"]),
                             {"we": 0, "wn": 0, "ce": 0, "cn": 0, "clip": []})
        c["we"] += edits(ref_w, hyp_w)
        c["wn"] += len(ref_w)
        c["ce"] += edits(ref_c, hyp_c)
        c["cn"] += len(ref_c)
        c["clip"].append(100 * edits(ref_w, hyp_w) / len(ref_w) if ref_w else 0)
        latency[r["model"]].append(r["ms"])

    m0, m1 = models[0], models[1]
    head = (f"| Language | Clips | {m0.title()} WER | {m0.title()} CER | "
            f"{m1.title()} WER | {m1.title()} CER | dWER | dCER |")
    lines = [head, "|---|---|---|---|---|---|---|---|"]
    for lang in langs:
        c0, c1 = cells.get((lang, m0)), cells.get((lang, m1))
        if not c0 or not c1:
            continue
        w0, r0 = wer_cer(c0)
        w1, r1 = wer_cer(c1)
        name = NAME.get(lang, lang)
        lines.append(f"| {name} | {len(c0['clip'])} | {w0:.2f}% | {r0:.2f}% | "
                     f"{w1:.2f}% | {r1:.2f}% | {w1 - w0:+.2f} | {r1 - r0:+.2f} |")

    def pooled(m):
        we = sum(cells[(l, m)]["we"] for l in langs if (l, m) in cells)
        wn = sum(cells[(l, m)]["wn"] for l in langs if (l, m) in cells)
        ce = sum(cells[(l, m)]["ce"] for l in langs if (l, m) in cells)
        cn = sum(cells[(l, m)]["cn"] for l in langs if (l, m) in cells)
        return (100 * we / wn if wn else 0.0), (100 * ce / cn if cn else 0.0)

    def macro(m):
        per = [wer_cer(cells[(l, m)]) for l in langs if (l, m) in cells]
        w = sum(x[0] for x in per) / len(per) if per else 0.0
        c = sum(x[1] for x in per) / len(per) if per else 0.0
        return w, c

    total = sum(len(cells[(l, m0)]["clip"]) for l in langs if (l, m0) in cells)
    pw0, pc0 = pooled(m0)
    pw1, pc1 = pooled(m1)
    lines.append(f"| Pooled | {total} | {pw0:.2f}% | {pc0:.2f}% | "
                 f"{pw1:.2f}% | {pc1:.2f}% | {pw1 - pw0:+.2f} | {pc1 - pc0:+.2f} |")
    if len(langs) > 1:
        mw0, mc0 = macro(m0)
        mw1, mc1 = macro(m1)
        lines.append(f"| Language macro | {total} | {mw0:.2f}% | {mc0:.2f}% | "
                     f"{mw1:.2f}% | {mc1:.2f}% | {mw1 - mw0:+.2f} | {mc1 - mc0:+.2f} |")

    lines.append("")
    lines.append(f"Median warm processing time per clip: "
                 f"{m0} {median(latency[m0][1:]):.1f} ms, {m1} {median(latency[m1][1:]):.1f} ms.")
    text = "\n".join(lines) + "\n"
    out = args.out or args.results[0].parent / "summary.md"
    out.write_text(text)
    print(text)


if __name__ == "__main__":
    main()
