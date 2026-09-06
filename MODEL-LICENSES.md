# Model licenses

TapTalk ships **no model weights**. Nothing model-shaped is inside the app bundle, the DMG,
or this repository. Models are downloaded by the end user's machine, on explicit action, from
the upstream host - so each user receives the weights directly from the publisher under that
publisher's own grant.

This file records the terms of every model TapTalk can download, so they live somewhere
auditable rather than only in prose. `README.md` carries the user-facing attribution.

| Model | Source | License | Role |
|---|---|---|---|
| Parakeet TDT 0.6B v3 | `FluidInference/parakeet-tdt-0.6b-v3-coreml` (NVIDIA upstream) | CC-BY-4.0 | Default engine - English + European |
| Nemotron 3.5 ASR Streaming Multilingual 0.6B | `FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML` (NVIDIA upstream) | OpenMDW-1.1 | Multilingual engine - Hindi and beyond |
| Parakeet Realtime EOU 120M | `FluidInference/parakeet-realtime-eou-120m-coreml` (NVIDIA upstream) | NVIDIA Open Model License | Optional live-typing add-on |
| Qwen 2.5 1.5B Instruct (GGUF) | `Qwen/Qwen2.5-1.5B-Instruct-GGUF` | Apache-2.0 | Smart Mode rewrite |

Runtime code: FluidAudio (Apache-2.0), llama.cpp (MIT), TapTalk itself (MIT).

## What each license actually requires

**CC-BY-4.0** (Parakeet) - attribution: creator, copyright notice, license notice, warranty
disclaimer, a URI, and an indication of modification. Discharged by the attribution section in
`README.md`. Conditions attach to distribution of the material; TapTalk distributes none.

**OpenMDW-1.1** (Nemotron multilingual) - one affirmative duty: *"If you distribute any portion
of the Model Materials, you shall retain in your distribution (1) a copy of this agreement, and
(2) all copyright notices and other notices of origin."* TapTalk distributes no portion, so it
does not trigger. Permissive otherwise - no commercial restriction, no copyleft, no acceptable-use
clause, and outputs are explicitly unencumbered. One behavioural restriction: all grants terminate
if you sue anyone alleging the model infringes a patent **or copyright**. Broader than Apache-2.0;
worth knowing before adopting any IP-litigation posture.

**NVIDIA Open Model License** (Parakeet EOU) - the strictest thing in the stack. Requires a
`Notice` file on redistribution, binds the licensee to NVIDIA's Trustworthy AI terms,
auto-terminates if safety guardrails are circumvented, requires the licensee to **indemnify
NVIDIA**, sets Santa Clara County as exclusive jurisdiction, and permits unilateral amendment.
Again gated on redistribution, which TapTalk does not do.

## The line that must not be crossed

"Model Materials" under OpenMDW includes *"all related artifacts (including associated data,
documentation and software)."* That means committing a `tokenizer.json`, `config.json` or
`manifest.json` into this repository would trigger the distribution clause exactly as weights
would - as would pasting a model card's benchmark tables into the README.

**Keep model artifacts out of the repo.** If TapTalk ever mirrors weights, ships an offline
installer, or proxies downloads, this file stops being sufficient and the full license texts must
travel with the artifacts. Note that neither NVIDIA's nor FluidInference's HuggingFace repos ship
a LICENSE file, so those texts would have to be sourced separately.

## Known limitation: downloads are not revision-pinned

FluidAudio constructs download URLs as `<base>/<repo>/resolve/main/<file>`
(`ModelRegistry.resolveModel`). The registry base URL is overridable, but **the revision is
hardcoded to `main`** - there is no way to pin a commit SHA without forking the dependency.

Two consequences, both accepted deliberately:

- An upstream re-upload changes what users receive, with no version handshake on our side.
- If a repository were gated or removed, first-run downloads would fail. The Nemotron model card
  still carries access-request language even though the API reports it ungated and anonymous
  download works, so this is not purely hypothetical.

Revisit if either upstream repo changes access terms.
