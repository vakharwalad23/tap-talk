#!/usr/bin/env python3
# Score every regression run in reports/_raw with Nathan's pinned scorer, next to his published
# per-model hypotheses (Parakeet, Orukeet baseline, greedy, NeMo FP32) on the same 128 clips.
import argparse
import collections
import json
import sys
from pathlib import Path

CORPORA = {"a": ("fleurs-a", "fleurs"), "b": ("fleurs-b", "holdout")}
NATHAN_LABELS = {"parakeet": "nathan/parakeet", "orukeet": "nathan/baseline", "orukeet-greedy": "nathan/greedy"}


def load_scorer(lab: Path):
    sys.path.insert(0, str(lab / "vendor/orukeet/evaluation/standard_asr"))
    from scoring import counts  # noqa: E402

    return counts


def references(lab: Path, corpus: str):
    manifest = json.loads((lab / "data" / CORPORA[corpus][0] / "manifest.json").read_text())
    return {row["sha256"]: row for row in manifest["fixtures"]}


def nathan_hypotheses(lab: Path, corpus: str):
    ev = lab / "vendor/orukeet/evidence/coreml-taptalk-20260915" / CORPORA[corpus][1]
    groups = collections.defaultdict(dict)
    for row in json.loads((ev / "coreml.json").read_text())["measurements"]:
        label = NATHAN_LABELS.get(row["model"], f"nathan/{row['model']}")
        groups[label][row["audioSHA256"]] = row["text"]
    for row in json.loads((ev / "nemo.json").read_text()):
        groups["nathan/nemo-fp32"][row["sha256"]] = row["text"]
    return groups


def our_hypotheses(lab: Path, corpus: str):
    groups = {}
    for path in sorted((lab / "reports/_raw").glob(f"*-{corpus}.json")):
        label = path.name[: -len(f"-{corpus}.json")]
        groups[label] = {row["sha256"]: row["text"] for row in json.loads(path.read_text())}
    return groups


def score(counts, refs, hyps):
    per_language = collections.defaultdict(lambda: {"words": 0, "errors": 0})
    for digest, ref in refs.items():
        text = hyps.get(digest, "")
        c = counts(ref["reference"], text, ref["language"])
        per_language[ref["language"]]["words"] += c["words"]
        per_language[ref["language"]]["errors"] += c["errors"]
    words = sum(v["words"] for v in per_language.values())
    errors = sum(v["errors"] for v in per_language.values())
    return {"words": words, "errors": errors, "wer": errors / words if words else 0.0,
            "languages": dict(sorted(per_language.items()))}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lab", type=Path, required=True)
    ap.add_argument("--identical", default="shipped-greedy=nathan/greedy",
                    help="ours=theirs: report text differences between two labels")
    args = ap.parse_args()
    counts = load_scorer(args.lab)
    results = {}
    texts = {}
    for corpus in CORPORA:
        refs = references(args.lab, corpus)
        groups = dict(nathan_hypotheses(args.lab, corpus))
        groups.update(our_hypotheses(args.lab, corpus))
        for label, hyps in groups.items():
            results.setdefault(label, {})[corpus] = score(counts, refs, hyps)
            texts.setdefault(label, {}).update(hyps)
    languages = sorted({lang for r in results.values() for c in r.values() for lang in c["languages"]})
    lines = ["| model | " + " | ".join(languages) + " | A errors | B errors | total errors / words | WER |",
             "|---|" + "---|" * len(languages) + "---|---|---|---|"]
    for label, per in sorted(results.items()):
        a, b = per.get("a"), per.get("b")
        cells = []
        for lang in languages:
            e = sum(c["languages"].get(lang, {}).get("errors", 0) for c in per.values())
            cells.append(str(e))
        errors = sum(c["errors"] for c in per.values())
        words = sum(c["words"] for c in per.values())
        lines.append(f"| {label} | " + " | ".join(cells) + f" | {a['errors'] if a else '-'} | {b['errors'] if b else '-'} | "
                     f"{errors} / {words} | {100 * errors / words:.2f} |")
    table = "\n".join(lines)
    print(table)

    diff_lines = []
    if "=" in args.identical:
        ours, theirs = args.identical.split("=", 1)
        if ours in texts and theirs in texts:
            mismatches = [(d, texts[ours][d], texts[theirs][d]) for d in texts[theirs] if texts[ours].get(d) != texts[theirs][d]]
            diff_lines.append(f"\n{ours} vs {theirs}: {len(mismatches)} of {len(texts[theirs])} transcripts differ")
            for digest, mine, other in mismatches:
                diff_lines.append(f"- {digest[:12]}\n  ours:   {mine}\n  theirs: {other}")
    diff = "\n".join(diff_lines)
    print(diff)

    reports = args.lab / "reports"
    reports.mkdir(exist_ok=True)
    (reports / "score.json").write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    (reports / "score.md").write_text(table + "\n" + diff + "\n")
    print(f"wrote {reports / 'score.md'}")


if __name__ == "__main__":
    main()
