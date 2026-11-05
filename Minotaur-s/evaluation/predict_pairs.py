#!/usr/bin/env python3
"""Produce calibration logits or evaluate known regressions using local checkpoint files."""
import argparse
import json
from pathlib import Path
from dataset import read, validate, write

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("dataset"); p.add_argument("--checkpoint", type=Path, required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--regression", action="store_true")
    p.add_argument("--device", choices=["cpu", "mps", "auto"], default="auto")
    args = p.parse_args()
    rows = read(args.dataset)
    if args.regression:
        if any(r.get("split") != "regression" for r in rows): raise ValueError("Only known regression records allowed")
    else:
        validate(rows, require_reviewed=True)
        if any(r.get("split") != "calibration" for r in rows): raise ValueError("Only calibration claims may produce temperature-fit observations")
    import torch
    from transformers import AutoModelForSequenceClassification, AutoTokenizer
    device = args.device if args.device != "auto" else "mps" if torch.backends.mps.is_available() else "cpu"
    tokenizer = AutoTokenizer.from_pretrained(args.checkpoint, local_files_only=True)
    model = AutoModelForSequenceClassification.from_pretrained(args.checkpoint, local_files_only=True).to(device).eval()
    labels = [model.config.id2label[i].lower() for i in range(3)]
    if labels != ["entailment", "neutral", "contradiction"]: raise ValueError("Unexpected empirical label order")
    observations = []
    with torch.inference_mode():
        for row in rows:
            pairs = [{"premise": row["premise"], "hypothesis": row["hypothesis"]}] if args.regression else row.get("pairs", [])
            for pair in pairs:
                inputs = tokenizer(pair["premise"], pair["hypothesis"], return_tensors="pt", max_length=512, truncation="only_first")
                logits = model(**{k: v.to(device) for k, v in inputs.items()}).logits.cpu()[0].tolist()
                prediction = labels[max(range(3), key=logits.__getitem__)]
                observation = {"claim_id": row["id"], "split": row["split"], "logits": logits,
                               "prediction": prediction, "reviewers": row.get("reviewers", [])}
                if args.regression: observation["correct"] = prediction in row["allowed_labels"]
                else: observation["label"] = pair["label"]
                observations.append(observation)
    write(args.output, observations)
    print(json.dumps({"observations": len(observations), "correct": sum(r.get("correct", False) for r in observations) if args.regression else None}))

if __name__ == "__main__": main()
