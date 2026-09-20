#!/usr/bin/env python3
# Export a joint decision graph that scores K encoder frames against one decoder projection per
# call. Same math as the single-step joint; adds the blank logit and the full-vocabulary
# log-sum-exp per frame so decode-time rescoring never needs the 8193 logits.
import argparse
import json
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
import torch

CONV = Path(__file__).resolve().parents[1] / "vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml"
sys.path.insert(0, str(CONV))
from individual_components import JointWrapper  # noqa: E402


class JointDecisionBatched(torch.nn.Module):
    def __init__(self, joint: JointWrapper, vocab_size: int, num_extra: int) -> None:
        super().__init__()
        self.joint = joint
        self.vocab_with_blank = int(vocab_size) + 1
        self.num_extra = int(num_extra)

    def forward(self, encoder_steps: torch.Tensor, decoder_step: torch.Tensor):
        logits = self.joint(encoder_steps, decoder_step)  # [1, K, 1, V + 1 + extra]
        token_logits = logits[..., : self.vocab_with_blank]
        duration_logits = logits[..., -self.num_extra :]
        token_id = torch.argmax(token_logits, dim=-1).to(torch.int32)  # [1, K, 1]
        probs = torch.softmax(token_logits, dim=-1)
        token_prob = torch.gather(probs, -1, token_id.long().unsqueeze(-1)).squeeze(-1)
        duration = torch.argmax(duration_logits, dim=-1).to(torch.int32)
        blank_logit = token_logits[..., self.vocab_with_blank - 1]
        logsumexp = torch.logsumexp(token_logits, dim=-1)
        return token_id, token_prob, duration, blank_logit, logsumexp


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--nemo", type=Path, required=True)
    ap.add_argument("--k", type=int, default=8)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    import nemo.collections.asr as nemo_asr

    model = nemo_asr.models.EncDecRNNTBPEModel.restore_from(str(args.nemo), map_location="cpu")
    model.eval()
    vocab_size = int(model.tokenizer.vocab_size)
    num_extra = int(model.joint.num_extra_outputs)
    hidden = int(model.encoder.d_model) if hasattr(model.encoder, "d_model") else 1024
    pred_hidden = int(model.decoder.pred_hidden)
    wrapper = JointDecisionBatched(JointWrapper(model.joint.eval()), vocab_size, num_extra).eval()

    enc = torch.randn(1, hidden, args.k, dtype=torch.float32)
    dec = torch.randn(1, pred_hidden, 1, dtype=torch.float32)
    with torch.inference_mode():
        traced = torch.jit.trace(wrapper, (enc.clone(), dec.clone()))
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="encoder_steps", shape=(1, hidden, args.k), dtype=np.float32),
            ct.TensorType(name="decoder_step", shape=(1, pred_hidden, 1), dtype=np.float32),
        ],
        outputs=[
            ct.TensorType(name="token_id", dtype=np.int32),
            ct.TensorType(name="token_prob", dtype=np.float32),
            ct.TensorType(name="duration", dtype=np.int32),
            ct.TensorType(name="blank_logit", dtype=np.float32),
            ct.TensorType(name="logsumexp", dtype=np.float32),
        ],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.CPU_ONLY,
    )
    mlmodel.short_description = f"Orukeet TDT joint decision, {args.k} encoder frames per call"
    args.out.mkdir(parents=True, exist_ok=True)
    package = args.out / f"JointDecisionBatchedK{args.k}.mlpackage"
    compiled = args.out / f"JointDecisionBatchedK{args.k}.mlmodelc"
    mlmodel.save(str(package))
    ct.models.utils.compile_model(str(package), destination_path=str(compiled))

    # Trace-time parity: Core ML (CPU) against the PyTorch wrapper on the trace input.
    with torch.inference_mode():
        ref = wrapper(enc, dec)
    got = mlmodel.predict({"encoder_steps": enc.numpy(), "decoder_step": dec.numpy()})
    checks = {
        "token_id_match": bool(np.array_equal(got["token_id"].astype(np.int32), ref[0].numpy())),
        "duration_match": bool(np.array_equal(got["duration"].astype(np.int32), ref[2].numpy())),
        "token_prob_max_abs_diff": float(np.max(np.abs(got["token_prob"] - ref[1].numpy()))),
        "logsumexp_max_abs_diff": float(np.max(np.abs(got["logsumexp"] - ref[4].numpy()))),
    }
    receipt = {"k": args.k, "vocab_size": vocab_size, "num_extra": num_extra, "checks": checks,
               "coremltools": ct.__version__, "torch": torch.__version__}
    (args.out / f"JointDecisionBatchedK{args.k}.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
