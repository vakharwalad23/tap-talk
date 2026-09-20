SHELL := /usr/bin/env bash
LAB := $(CURDIR)
CONV := $(LAB)/vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml
PY := uv run --project $(LAB) python
BENCHPY := uv run --project $(LAB)/bench python

NEMO := $(LAB)/work/orukeet-v0.1.0.nemo
EXPORT := $(LAB)/out/export
ENCODERS := $(LAB)/out/encoders
JOINT := $(LAB)/out/joint
BUNDLES := $(LAB)/out/bundles
FIXTURES := $(LAB)/data/fixtures
RAW := $(LAB)/reports/_raw

# Nathan's published greedy bundle, fetched and compiled into the lab (make shipped); the
# reference every variant is measured against, so the repo reproduces without a TapTalk install.
SHIPPED := $(LAB)/models/shipped-greedy
VOCAB := $(SHIPPED)/parakeet_vocab.json
DIR ?= $(SHIPPED)
UNITS ?= ane
K ?= 8

.PHONY: help setup nemo shipped export int8 int8-asym greedy-joint bundles build profile vendor corpus reg reg-all score joint-batched audit clean

help:
	@echo "Orukeet Core ML lab: variants built from the r3 .nemo, measured against the shipped greedy bundle"
	@echo ""
	@echo "  make setup          vendor the mobius converter source and sync the lab uv environments"
	@echo "  make nemo           download and verify the r3 .nemo into work/"
	@echo "  make shipped        fetch, verify and compile the published greedy bundle into models/"
	@echo "  make export         FP16 Core ML components from the .nemo into out/export/"
	@echo "  make int8           int8 per-channel symmetric encoder into out/encoders/"
	@echo "  make int8-asym      int8 asymmetric encoder (the June recipe) for the latency A/B"
	@echo "  make greedy-joint   prune top-K outputs from the single-step joint"
	@echo "  make bundles        assemble compiled bundles into out/bundles/<name>/"
	@echo "  make build          build ttprof and ttreg"
	@echo "  make profile        latency of DIR (default: the shipped bundle); UNITS=ane|gpu|cpu, AUDIO=clip.wav"
	@echo "  make vendor         sparse-clone Nathan's PR branch (corpus sealer, scorer, evidence) and fixtures"
	@echo "  make corpus         seal both 64-clip FLEURS corpora and verify against Nathan's manifests"
	@echo "  make reg            transcribe both corpora with DIR, LABEL=<name> (writes reports/_raw/<LABEL>-{a,b}.json)"
	@echo "  make reg-all        reg for the shipped bundle and every bundle under out/bundles/"
	@echo "  make score          score every reports/_raw run against Nathan's numbers"
	@echo "  make joint-batched  export the K-frame joint (K=8 default) into out/joint/"
	@echo "  make audit          parity audit of the batched joint against the shipped single-step joint"
	@echo "  make clean          remove out/, raw results and the Swift build"

setup:
	bash convert/vendor_mobius.sh
	uv sync --project $(LAB)
	uv sync --project $(LAB)/bench

nemo:
	bash convert/fetch_nemo.sh "$(NEMO)"

shipped:
	bash convert/fetch_shipped.sh greedy

export:
	bash convert/export.sh "$(NEMO)" "$(EXPORT)"

int8:
	mkdir -p "$(ENCODERS)"
	$(PY) $(LAB)/convert/quantize_encoder.py --src "$(EXPORT)/parakeet_encoder.mlpackage" --dst "$(ENCODERS)/int8sym.mlpackage" --mode linear_symmetric

int8-asym:
	mkdir -p "$(ENCODERS)"
	$(PY) $(LAB)/convert/quantize_encoder.py --src "$(EXPORT)/parakeet_encoder.mlpackage" --dst "$(ENCODERS)/int8asym.mlpackage" --mode linear

greedy-joint:
	mkdir -p "$(JOINT)"
	$(PY) $(LAB)/convert/prune_joint.py --src "$(EXPORT)/parakeet_joint_decision_single_step.mlpackage" --dst "$(JOINT)/greedy.mlpackage"

# One bundle per encoder variant; decoder, preprocessor and greedy joint are shared.
bundles: greedy-joint shipped
	$(BENCHPY) convert/assemble_bundle.py --preprocessor "$(EXPORT)/parakeet_preprocessor.mlpackage" --encoder "$(ENCODERS)/int8sym.mlpackage" --decoder "$(EXPORT)/parakeet_decoder.mlpackage" --joint "$(JOINT)/greedy.mlpackage" --vocab "$(VOCAB)" --out "$(BUNDLES)/orukeet-int8sym-greedy"
	$(BENCHPY) convert/assemble_bundle.py --preprocessor "$(EXPORT)/parakeet_preprocessor.mlpackage" --encoder "$(EXPORT)/parakeet_encoder.mlpackage" --decoder "$(EXPORT)/parakeet_decoder.mlpackage" --joint "$(JOINT)/greedy.mlpackage" --vocab "$(VOCAB)" --out "$(BUNDLES)/orukeet-fp16-greedy"
	@if [ -d "$(ENCODERS)/int8asym.mlpackage" ]; then $(BENCHPY) convert/assemble_bundle.py --preprocessor "$(EXPORT)/parakeet_preprocessor.mlpackage" --encoder "$(ENCODERS)/int8asym.mlpackage" --decoder "$(EXPORT)/parakeet_decoder.mlpackage" --joint "$(JOINT)/greedy.mlpackage" --vocab "$(VOCAB)" --out "$(BUNDLES)/orukeet-int8asym-greedy"; fi

build:
	swift build --package-path swift -c release

profile: build
	swift/.build/release/ttprof --dir "$(DIR)" --encoder-units $(UNITS) --components --runs 20 $(if $(AUDIO),--audio "$(AUDIO)",)

vendor:
	bash bench/vendor.sh

corpus:
	bash bench/corpus.sh

reg: build
	@test -n "$(LABEL)" || { echo "set LABEL=<name>"; exit 1; }
	mkdir -p "$(RAW)"
	swift/.build/release/ttreg --bundle "$(DIR)" --manifest data/fleurs-a/manifest.json --out "$(RAW)/$(LABEL)-a.json"
	swift/.build/release/ttreg --bundle "$(DIR)" --manifest data/fleurs-b/manifest.json --out "$(RAW)/$(LABEL)-b.json"

reg-all: build shipped
	$(MAKE) reg DIR="$(SHIPPED)" LABEL=shipped-greedy
	@for d in $(BUNDLES)/*/; do n=$$(basename "$$d"); $(MAKE) reg DIR="$$d" LABEL="$$n"; done

score:
	$(BENCHPY) bench/score.py --lab "$(LAB)"

joint-batched:
	mkdir -p "$(JOINT)"
	$(PY) $(LAB)/convert/export_batched_joint.py --nemo "$(NEMO)" --k $(K) --out "$(JOINT)"

audit: shipped
	mkdir -p reports
	$(PY) $(LAB)/convert/audit_batched_joint.py --bundle "$(SHIPPED)" --batched "$(JOINT)/JointDecisionBatchedK$(K).mlmodelc" --k $(K) --fixtures "$(FIXTURES)" --out reports/audit-k$(K).json

clean:
	rm -rf out reports/_raw* swift/.build
