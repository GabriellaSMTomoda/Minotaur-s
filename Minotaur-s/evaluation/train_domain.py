#!/usr/bin/env python3
"""Resume local supervised BERTimbau fine-tuning. No paid GPU, LLM or hidden test access."""
from __future__ import annotations
import argparse
import hashlib
import json
import random
from pathlib import Path
from dataset import fingerprint, read, validate

LABELS = ("entailment", "neutral", "contradiction")

def prepare_records(path):
    rows = read(path)
    validate(rows, require_reviewed=True)
    if {r.get("split") for r in rows} - {"train", "calibration"}:
        raise ValueError("Training input must not contain blind test or known regression cases")
    train = [(r["id"], p) for r in rows if r["split"] == "train" for p in r.get("pairs", [])]
    dev = [(r["id"], p) for r in rows if r["split"] == "calibration" for p in r.get("pairs", [])]
    if not train or not dev or {p["label"] for _, p in train} != set(LABELS):
        raise ValueError("Reviewed train and calibration pairs covering all three labels are required")
    return train, dev, fingerprint(rows)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path, help="Train + calibration only, with passage-level NLI labels")
    parser.add_argument("--checkpoint", type=Path, required=True, help="Existing validated local three-class checkpoint")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--learning-rate", type=float, default=2e-5)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--device", choices=["cpu", "mps", "auto"], default="auto")
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    # Check data before importing/downloading ML dependencies or touching large artifacts.
    train, dev, digest = prepare_records(args.dataset)
    if not args.checkpoint.is_dir():
        raise ValueError("Validated baseline checkpoint not present locally")
    import torch
    from transformers import AutoModelForSequenceClassification, AutoTokenizer
    random.seed(args.seed); torch.manual_seed(args.seed)
    torch.set_num_threads(min(8, torch.get_num_threads()))
    device = args.device if args.device != "auto" else "mps" if torch.backends.mps.is_available() else "cpu"
    tokenizer = AutoTokenizer.from_pretrained(args.checkpoint, local_files_only=True)
    model = AutoModelForSequenceClassification.from_pretrained(args.checkpoint, local_files_only=True)
    if model.config.model_type != "bert" or model.config.num_labels != 3:
        raise ValueError("Expected existing three-class BERTimbau-base architecture")
    if [model.config.id2label[i].lower() for i in range(3)] != list(LABELS):
        raise ValueError("Empirically validated label order must be entailment, neutral, contradiction")
    model.to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate, weight_decay=.01)
    args.output.mkdir(parents=True, exist_ok=True)
    resume_path = args.output / "latest.pt"
    epoch_start, batch_start, step, best = 0, 0, 0, -1.0
    if args.resume:
        state = torch.load(resume_path, map_location="cpu", weights_only=True)
        if state["dataset_sha256"] != digest:
            raise ValueError("Cannot resume against a changed corpus")
        model.load_state_dict(state["model"]); optimizer.load_state_dict(state["optimizer"])
        epoch_start, batch_start, step, best = state["epoch"], state["next_batch"], state["step"], state["best"]
        torch.set_rng_state(state["torch_rng"])
        if device == "mps" and "mps_rng" in state:
            torch.mps.set_rng_state(state["mps_rng"])

    def batch(records):
        pairs = [p for _, p in records]
        encoded = tokenizer([p["premise"] for p in pairs], [p["hypothesis"] for p in pairs],
                            padding=True, truncation="only_first", max_length=512, return_tensors="pt")
        encoded["labels"] = torch.tensor([LABELS.index(p["label"]) for p in pairs])
        return {k: v.to(device) for k, v in encoded.items()}

    def save(epoch, next_batch):
        state = {"model": model.state_dict(), "optimizer": optimizer.state_dict(), "epoch": epoch,
                 "next_batch": next_batch, "step": step, "best": best, "dataset_sha256": digest,
                 "torch_rng": torch.get_rng_state()}
        if device == "mps": state["mps_rng"] = torch.mps.get_rng_state()
        temporary = resume_path.with_suffix(".tmp")
        torch.save(state, temporary); temporary.replace(resume_path)

    def evaluate():
        model.eval(); confusion = [[0] * 3 for _ in range(3)]
        with torch.inference_mode():
            for offset in range(0, len(dev), args.batch_size):
                encoded = batch(dev[offset:offset + args.batch_size])
                predicted = model(**encoded).logits.argmax(-1).cpu().tolist()
                expected = encoded["labels"].cpu().tolist()
                for a, b in zip(expected, predicted): confusion[a][b] += 1
        values = []
        for c in range(3):
            tp = confusion[c][c]; denominator = sum(confusion[c]) + sum(r[c] for r in confusion)
            values.append(2 * tp / denominator if denominator else 0)
        return sum(values) / 3

    next_epoch, next_batch = epoch_start, batch_start
    try:
        for epoch in range(epoch_start, args.epochs):
            order = list(range(len(train))); random.Random(args.seed + epoch).shuffle(order)
            model.train()
            for offset in range(batch_start if epoch == epoch_start else 0, len(train), args.batch_size):
                optimizer.zero_grad(set_to_none=True)
                model(**batch([train[i] for i in order[offset:offset + args.batch_size]])).loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
                optimizer.step(); step += 1
                next_epoch, next_batch = epoch, offset + args.batch_size
                if step % 25 == 0: save(next_epoch, next_batch)
            score = evaluate()
            print(json.dumps({"epoch": epoch + 1, "calibration_macro_f1": score}), flush=True)
            if score > best:
                best = score
                model.save_pretrained(args.output / "checkpoint-best")
                tokenizer.save_pretrained(args.output / "checkpoint-best")
            next_epoch, next_batch = epoch + 1, 0
            save(next_epoch, next_batch)
    except KeyboardInterrupt:
        save(next_epoch, next_batch)
        raise SystemExit("Interrupted; resume with --resume")
    weights = args.output / "checkpoint-best" / "model.safetensors"
    with weights.open("rb") as stream:
        weight_digest = hashlib.file_digest(stream, "sha256").hexdigest()
    summary = {"status": "COMPLETE", "selected_checkpoint": str((args.output / "checkpoint-best").resolve()),
               "dataset_sha256": digest, "seed": args.seed, "best_calibration_macro_f1": best,
               "model_version": "bertimbau-domain-" + digest[:8] + "-" + weight_digest[:12], "label_order": list(LABELS),
               "weights_sha256": weight_digest,
               "promotion_status": "requires_coreml_parity_adversarial_and_physical_device_gates"}
    (args.output / "training_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    (args.output / "checkpoint-best" / "selection.json").write_text(json.dumps(summary, indent=2) + "\n")

if __name__ == "__main__":
    main()
