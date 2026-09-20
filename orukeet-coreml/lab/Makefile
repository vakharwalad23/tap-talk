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
RUNS ?= 10
PKG ?= $(LAB)/models/shipped-greedy-packages/Encoder.mlpackage
SECONDS ?= 5
EXPORT_WINDOW := $(LAB)/out/export-$(SECONDS)s
WINDOW_AUDIO ?= data/fleurs-a/en_us-10233995782544396174.wav data/fleurs-b/en_us-1038214857203833067.wav
PENALTIES ?= 0.5 1.0 1.5 2.0
DECODE_FLAGS = $(if $(JOINT),--joint "$(JOINT)",) $(if $(FUSED),--fused "$(FUSED)",) $(if $(PENALTY),--blank-penalty $(PENALTY),) $(foreach w,$(WINDOWS),--window "$(w)")

.PHONY: help setup nemo shipped export export-window int8 int8-asym greedy-joint bundles build profile warm warm-first decode decode-reg vendor corpus reg reg-all score joint-batched fused audit audit-window shipped-baseline window-compile sweep fused clean

help:
	@echo "Orukeet Core ML lab: variants built from the r3 .nemo, measured against the shipped greedy bundle"
	@echo ""
	@echo "  make setup          vendor the mobius converter source and sync the lab uv environments"
	@echo "  make nemo           download and verify the r3 .nemo into work/"
	@echo "  make shipped        fetch, verify and compile the published greedy bundle into models/"
	@echo "  make shipped-baseline  same for the baseline profile (joint with top-K outputs)"
	@echo "  make export         FP16 Core ML components from the .nemo into out/export/"
	@echo "  make export-window  FP16 components at a shorter fixed window; SECONDS=5|10, out/export-<n>s/"
	@echo "  make int8           int8 per-channel symmetric encoder into out/encoders/"
	@echo "  make int8-asym      int8 asymmetric encoder (the June recipe) for the latency A/B"
	@echo "  make greedy-joint   prune top-K outputs from the single-step joint"
	@echo "  make bundles        assemble compiled bundles into out/bundles/<name>/"
	@echo "  make build          build ttprof and ttreg"
	@echo "  make profile        latency of DIR (default: the shipped bundle); UNITS=ane|gpu|cpu, AUDIO=clip.wav"
	@echo "  make warm           pick encoder placement (ane vs gpu) for DIR; RUNS=10 default, prints installer JSON"
	@echo "  make warm-first     first-load cost of PKG through a fresh compile; PKG=<path to .mlpackage>"
	@echo "  make decode         own decode loop on DIR: AUDIO=clip.wav for timing; WINDOWS=<dirs> FUSED=<mlmodelc> PENALTY=<x> JOINT=<batched> optional"
	@echo "  make decode-reg     own decode loop over both corpora, LABEL=<name>; same options as decode"
	@echo "  make vendor         sparse-clone Nathan's PR branch (corpus sealer, scorer, evidence) and fixtures"
	@echo "  make corpus         seal both 64-clip FLEURS corpora and verify against Nathan's manifests"
	@echo "  make reg            transcribe both corpora with DIR, LABEL=<name> (writes reports/_raw/<LABEL>-{a,b}.json)"
	@echo "  make reg-all        reg for the shipped bundle and every bundle under out/bundles/"
	@echo "  make score          score every reports/_raw run against Nathan's numbers"
	@echo "  make joint-batched  export the K-frame joint (K=8 default) into out/joint/"
	@echo "  make fused          fuse decoder+joint into one graph, parity-checked, into out/fused/"
	@echo "  make window-compile compile out/export-<n>s packages into out/windows/<n>s/ for decode WINDOWS=; SECONDS=\"5 10\""
	@echo "  make sweep          blank-penalty sweep over PENALTIES with the baseline joint (needs shipped-baseline)"
	@echo "  make audit          parity audit of the batched joint against the shipped single-step joint"
	@echo "  make audit-window   parity audit of a window export's encoder against the 15 s baseline"
	@echo "  make clean          remove out/, raw results and the Swift build"

setup:
	bash convert/vendor_mobius.sh
	uv sync --project $(LAB)
	uv sync --project $(LAB)/bench

nemo:
	bash convert/fetch_nemo.sh "$(NEMO)"

shipped:
	bash convert/fetch_shipped.sh greedy

shipped-baseline:
	bash convert/fetch_shipped.sh baseline

export:
	bash convert/export.sh "$(NEMO)" "$(EXPORT)"

export-window:
	mkdir -p "$(EXPORT_WINDOW)"
	@[ -d "$(EXPORT_WINDOW)/parakeet_encoder.mlpackage" ] || bash convert/export_window.sh "$(NEMO)" "$(SECONDS)" "$(EXPORT_WINDOW)"

audit-window: shipped
	mkdir -p reports
	$(PY) $(LAB)/convert/audit_window.py --full-preprocessor "$(PREPROCESSOR)" --full-encoder "$(EXPORT)/parakeet_encoder.mlpackage" --window-preprocessor "$(EXPORT_WINDOW)/parakeet_preprocessor.mlpackage" --window-encoder "$(EXPORT_WINDOW)/parakeet_encoder.mlpackage" --audio $(WINDOW_AUDIO) --window-seconds $(SECONDS) --out reports/audit-window-$(SECONDS)s.json

int8:
	mkdir -p "$(ENCODERS)"
	@[ -d "$(ENCODERS)/int8sym.mlpackage" ] || $(PY) $(LAB)/convert/quantize_encoder.py --src "$(EXPORT)/parakeet_encoder.mlpackage" --dst "$(ENCODERS)/int8sym.mlpackage" --mode linear_symmetric

int8-asym:
	mkdir -p "$(ENCODERS)"
	@[ -d "$(ENCODERS)/int8asym.mlpackage" ] || $(PY) $(LAB)/convert/quantize_encoder.py --src "$(EXPORT)/parakeet_encoder.mlpackage" --dst "$(ENCODERS)/int8asym.mlpackage" --mode linear

greedy-joint:
	mkdir -p "$(JOINT)"
	@[ -d "$(JOINT)/greedy.mlpackage" ] || $(PY) $(LAB)/convert/prune_joint.py --src "$(EXPORT)/parakeet_joint_decision_single_step.mlpackage" --dst "$(JOINT)/greedy.mlpackage"

# One bundle per encoder variant; decoder and greedy joint are shared. The preprocessor comes from
# the pinned release: it has no learned weights, and the mobius export of it takes a range-shaped
# input that runs about 8x slower on the CPU (11 ms vs 1.4 ms per clip). Outputs that already
# exist are kept, so re-running a target after a partial failure resumes where it stopped.
PREPROCESSOR := $(LAB)/models/shipped-greedy-packages/Preprocessor.mlpackage
bundles: greedy-joint shipped
	$(BENCHPY) convert/assemble_bundle.py --preprocessor "$(PREPROCESSOR)" --encoder "$(ENCODERS)/int8sym.mlpackage" --decoder "$(EXPORT)/parakeet_decoder.mlpackage" --joint "$(JOINT)/greedy.mlpackage" --vocab "$(VOCAB)" --out "$(BUNDLES)/orukeet-int8sym-greedy"
	$(BENCHPY) convert/assemble_bundle.py --preprocessor "$(PREPROCESSOR)" --encoder "$(EXPORT)/parakeet_encoder.mlpackage" --decoder "$(EXPORT)/parakeet_decoder.mlpackage" --joint "$(JOINT)/greedy.mlpackage" --vocab "$(VOCAB)" --out "$(BUNDLES)/orukeet-fp16-greedy"
	@if [ -d "$(ENCODERS)/int8asym.mlpackage" ]; then $(BENCHPY) convert/assemble_bundle.py --preprocessor "$(PREPROCESSOR)" --encoder "$(ENCODERS)/int8asym.mlpackage" --decoder "$(EXPORT)/parakeet_decoder.mlpackage" --joint "$(JOINT)/greedy.mlpackage" --vocab "$(VOCAB)" --out "$(BUNDLES)/orukeet-int8asym-greedy"; fi

build:
	swift build --package-path swift -c release

profile: build
	swift/.build/release/ttprof --dir "$(DIR)" --encoder-units $(UNITS) --components --runs 20 $(if $(AUDIO),--audio "$(AUDIO)",)

warm: build
	swift/.build/release/ttwarm --dir "$(DIR)" --runs $(RUNS)

warm-first: build
	swift/.build/release/ttwarm --first-load "$(PKG)"

decode: build
	swift/.build/release/ttdecode --bundle "$(DIR)" $(DECODE_FLAGS) $(if $(AUDIO),--audio "$(AUDIO)" --runs 20,)

decode-reg: build
	@test -n "$(LABEL)" || { echo "set LABEL=<name>"; exit 1; }
	mkdir -p "$(RAW)"
	swift/.build/release/ttdecode --bundle "$(DIR)" $(DECODE_FLAGS) --manifest data/fleurs-a/manifest.json --out "$(RAW)/$(LABEL)-a.json"
	swift/.build/release/ttdecode --bundle "$(DIR)" $(DECODE_FLAGS) --manifest data/fleurs-b/manifest.json --out "$(RAW)/$(LABEL)-b.json"

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

fused:
	@[ -d out/fused ] || bash convert/fuse.sh "$(NEMO)" out/fused
	@for p in fp16 fp32; do [ -d "out/fused/decoder_joint_decision_$$p.mlmodelc" ] || xcrun coremlcompiler compile "out/fused/decoder_joint_decision_$$p.mlpackage" out/fused; done

window-compile:
	@for s in $(SECONDS); do d="out/windows/$${s}s"; mkdir -p "$$d"; \
	  [ -d "$$d/Preprocessor.mlmodelc" ] || { xcrun coremlcompiler compile "out/export-$${s}s/parakeet_preprocessor.mlpackage" "$$d" && mv "$$d/parakeet_preprocessor.mlmodelc" "$$d/Preprocessor.mlmodelc"; }; \
	  [ -d "$$d/Encoder.mlmodelc" ] || { xcrun coremlcompiler compile "out/export-$${s}s/parakeet_encoder.mlpackage" "$$d" && mv "$$d/parakeet_encoder.mlmodelc" "$$d/Encoder.mlmodelc"; }; done

sweep: build
	@for p in $(PENALTIES); do $(MAKE) decode-reg LABEL="penalty-$$p" JOINT="$(LAB)/models/shipped-baseline/JointDecisionv3.mlmodelc" PENALTY="$$p"; done

audit: shipped
	mkdir -p reports
	$(PY) $(LAB)/convert/audit_batched_joint.py --bundle "$(SHIPPED)" --batched "$(JOINT)/JointDecisionBatchedK$(K).mlmodelc" --k $(K) --fixtures "$(FIXTURES)" --out reports/audit-k$(K).json

clean:
	rm -rf out reports/_raw* swift/.build
