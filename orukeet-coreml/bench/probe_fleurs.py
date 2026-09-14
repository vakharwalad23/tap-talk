#!/usr/bin/env python3
# Verify the 25 FLEURS language codes by matching each test split's row count to the paper's table.
from huggingface_hub import hf_hub_download

REPO = "google/fleurs"
# code -> (display name, expected test clip count from the Orukeet paper table)
LANGS = [
    ("bg_bg", "Bulgarian", 658), ("hr_hr", "Croatian", 914), ("cs_cz", "Czech", 723),
    ("da_dk", "Danish", 930), ("nl_nl", "Dutch", 364), ("en_us", "English", 647),
    ("et_ee", "Estonian", 893), ("fi_fi", "Finnish", 918), ("fr_fr", "French", 676),
    ("de_de", "German", 862), ("el_gr", "Greek", 650), ("hu_hu", "Hungarian", 905),
    ("it_it", "Italian", 865), ("lv_lv", "Latvian", 851), ("lt_lt", "Lithuanian", 986),
    ("mt_mt", "Maltese", 926), ("pl_pl", "Polish", 758), ("pt_br", "Portuguese", 919),
    ("ro_ro", "Romanian", 883), ("ru_ru", "Russian", 775), ("sk_sk", "Slovak", 792),
    ("sl_si", "Slovenian", 834), ("es_419", "Spanish", 908), ("sv_se", "Swedish", 759),
    ("uk_ua", "Ukrainian", 750),
]


def rows(code):
    path = hf_hub_download(REPO, f"data/{code}/test.tsv", repo_type="dataset")
    return sum(1 for line in open(path, encoding="utf-8") if line.strip())


def main():
    total = 0
    ok = 0
    for code, name, expected in LANGS:
        try:
            n = rows(code)
        except Exception as e:
            print(f"MISS  {code:8} {name:12} error: {str(e)[:60]}")
            continue
        total += n
        near = abs(n - expected) <= max(5, expected * 0.03)
        ok += near
        flag = "ok" if near else "CHECK"
        print(f"{flag:5} {code:8} {name:12} rows={n:5} expected={expected:5} diff={n - expected:+d}")
    print(f"\n{ok}/{len(LANGS)} match; total rows={total} (paper pooled 20146)")


if __name__ == "__main__":
    main()
