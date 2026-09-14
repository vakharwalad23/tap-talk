SHELL := /usr/bin/env bash
S := scripts
CONV := vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml

LANGS ?= bg_bg,hr_hr,cs_cz,da_dk,nl_nl,en_us,et_ee,fi_fi,fr_fr,de_de,el_gr,hu_hu,it_it,lv_lv,lt_lt,mt_mt,pl_pl,pt_br,ro_ro,ru_ru,sk_sk,sl_si,es_419,sv_se,uk_ua
LIMIT ?= 0
FP32 := out/orukeet-tdt-0.6b-v3-coreml
INT8 := out/orukeet-tdt-0.6b-v3-coreml-int8

.PHONY: help preflight setup convert quantize models probe data build bench-run reports bench bench-quick data-ls bench-ls compare publish clean distclean

help:
	@echo "Orukeet Core ML: conversion and benchmark suite (Apple Silicon)"
	@echo ""
	@echo "  make preflight     check macOS arm64 and dependencies"
	@echo "  make setup         vendor the converter and build its env"
	@echo "  make convert       NeMo checkpoint to float32 Core ML bundle"
	@echo "  make quantize      build the int8 Core ML bundle"
	@echo "  make models        stage Parakeet (Hugging Face) and Orukeet for the bench"
	@echo "  make probe         verify FLEURS language codes against the paper counts"
	@echo "  make data          download FLEURS (LANGS=..., LIMIT=0 for all)"
	@echo "  make build         build the Swift benchmark harness"
	@echo "  make bench         build + models + run all passes + score reports"
	@echo "  make bench-quick   small smoke benchmark (en_us, 100 clips)"
	@echo "  make data-ls       download LibriSpeech test-clean and test-other"
	@echo "  make bench-ls      run and score the LibriSpeech benchmark"
	@echo "  make compare       compare FLEURS and LibriSpeech results to the paper"
	@echo "  make publish REPO=owner/name [PUSH=1]   push bundles to Hugging Face"
	@echo "  make clean         remove build output and staged models"
	@echo "  make distclean     also remove vendor env, downloads, and raw results"

preflight:
	bash $(S)/lib/preflight.sh xcode swift

setup:
	bash $(S)/convert/setup.sh

convert:
	bash $(S)/convert/convert.sh

quantize:
	bash $(S)/quantize/build_int8.sh

models:
	bash $(S)/bench/prep_models.sh

probe:
	uv run --project $(CONV) python $(S)/bench/probe_fleurs.py

data:
	uv run --project $(CONV) python $(S)/bench/fleurs_prep.py --langs $(LANGS) --limit $(LIMIT) --out data/fleurs-full

build:
	swift build --package-path swift -c release

bench-run:
	bash $(S)/bench/run_passes.sh

reports:
	bash $(S)/bench/make_reports.sh

bench: build models bench-run reports

bench-quick: build models
	uv run --project $(CONV) python $(S)/bench/fleurs_prep.py --langs en_us --limit 100 --out data/fleurs-quick
	MANIFEST=$(CURDIR)/data/fleurs-quick/manifest.jsonl RAW=$(CURDIR)/reports/_raw-quick bash $(S)/bench/run_passes.sh
	RAW=$(CURDIR)/reports/_raw-quick REPORT_DEST=$(CURDIR)/reports/quick bash $(S)/bench/make_reports.sh

data-ls:
	uv run --project $(CONV) python $(S)/bench/librispeech_prep.py --out data/librispeech

bench-ls: build models
	MANIFEST=$(CURDIR)/data/librispeech/manifest.jsonl RAW=$(CURDIR)/reports/_raw-ls bash $(S)/bench/run_passes.sh
	RAW=$(CURDIR)/reports/_raw-ls DEST=$(CURDIR)/reports/librispeech bash $(S)/bench/score_pair.sh

compare:
	python3 $(S)/bench/compare_paper.py \
	  --fleurs reports/fleurs-full/multilingual-int8/summary.md \
	  --librispeech reports/librispeech/int8/summary.md \
	  --out reports/COMPARISON.md

publish:
	@test -n "$(REPO)" || { echo "set REPO=owner/name"; exit 1; }
	python3 $(S)/publish/push_hf.py --repo $(REPO) --fp32 $(FP32) --int8 $(INT8) $(if $(PUSH),--push,)

clean:
	rm -rf swift/.build models work reports/_raw-quick reports/quick reports/_raw-ls reports/librispeech

distclean: clean
	rm -rf vendor out data reports/_raw
