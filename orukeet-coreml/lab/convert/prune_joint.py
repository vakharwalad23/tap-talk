#!/usr/bin/env python3
# Remove the top-K outputs and everything only they depend on from the single-step joint.
# Same transformation as optimize_joint.py in Oruk-AI/orukeet#6 (MIT), applied to the mobius
# export instead of the byte-identical FluidInference graph.
import argparse
import shutil
from pathlib import Path

import coremltools as ct

KEEP = ["token_id", "token_prob", "duration"]
GRAPH = "Data/com.apple.CoreML/model.mlmodel"


def prune(spec, keep):
    present = {o.name for o in spec.description.output}
    missing = set(keep) - present
    if missing:
        raise SystemExit(f"outputs missing from the joint: {sorted(missing)}")
    for function in spec.mlProgram.functions.values():
        for block in function.block_specializations.values():
            needed = set(keep)
            retained = []
            for op in reversed(block.operations):
                if op.blocks:
                    raise SystemExit("nested blocks are not expected in the joint graph")
                if needed.intersection(o.name for o in op.outputs):
                    retained.append(op)
                    for binding in op.inputs.values():
                        needed.update(a.name for a in binding.arguments if a.name)
            retained.reverse()
            del block.operations[:]
            block.operations.extend(retained)
            del block.outputs[:]
            block.outputs.extend(keep)
    outputs = [o for o in spec.description.output if o.name in keep]
    del spec.description.output[:]
    spec.description.output.extend(outputs)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, required=True)
    ap.add_argument("--dst", type=Path, required=True)
    args = ap.parse_args()
    if args.dst.exists():
        raise SystemExit(f"{args.dst} exists; remove it first")
    shutil.copytree(args.src, args.dst)
    spec = ct.utils.load_spec(str(args.dst / GRAPH))
    block = next(iter(spec.mlProgram.functions["main"].block_specializations.values()))
    before = len(block.operations)
    prune(spec, KEEP)
    after = len(block.operations)
    if any(op.type == "topk" for op in block.operations):
        raise SystemExit("topk still feeds a retained output")
    if [o.name for o in spec.description.output] != KEEP:
        raise SystemExit("unexpected outputs after pruning")
    ct.utils.save_spec(spec, str(args.dst / GRAPH))
    print(f"wrote {args.dst}: {before} -> {after} ops, outputs {KEEP}")


if __name__ == "__main__":
    main()
