#!/usr/bin/env python3
"""Fine-tune BERTimbau-base on PLUE/MNLI without paid infrastructure.

Model selection uses only PLUE's matched validation split. The adversarial
Spike 7 set is intentionally absent from this program and remains sealed until
the best checkpoint has been selected.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import platform
import random
import sys
import time
from collections import Counter
from contextlib import nullcontext
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import torch
from torch.utils.data import DataLoader, Dataset
from transformers import AutoModelForSequenceClassification, AutoTokenizer
from transformers.optimization import get_linear_schedule_with_warmup


LABEL2ID = {"entailment": 0, "neutral": 1, "contradiction": 2}
ID2LABEL = {value: key for key, value in LABEL2ID.items()}
MODEL_ID = "neuralmind/bert-base-portuguese-cased"
SCRIPT_DIR = Path(__file__).resolve().parent


@dataclass(frozen=True)
class Record:
    premise: str
    hypothesis: str
    label: int


class MNLIDataset(Dataset[Record]):
    def __init__(self, path: Path, limit: int | None = None, seed: int = 42):
        records: list[Record] = []
        skipped_empty = 0
        with path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            for row in reader:
                label_name = row["gold_label"].strip()
                if label_name not in LABEL2ID:
                    continue
                premise = row["sentence1"].strip()
                hypothesis = row["sentence2"].strip()
                if not premise or not hypothesis:
                    skipped_empty += 1
                    continue
                records.append(
                    Record(
                        premise=premise,
                        hypothesis=hypothesis,
                        label=LABEL2ID[label_name],
                    )
                )
        self.source_valid_records = len(records)
        self.skipped_empty = skipped_empty
        if limit is not None and limit < len(records):
            order = list(range(len(records)))
            random.Random(seed).shuffle(order)
            records = [records[index] for index in order[:limit]]
        self.records = records

    def __len__(self) -> int:
        return len(self.records)

    def __getitem__(self, index: int) -> Record:
        return self.records[index]


class PairCollator:
    def __init__(self, tokenizer: Any, max_length: int, pad_to_multiple_of: int | None):
        self.tokenizer = tokenizer
        self.max_length = max_length
        self.pad_to_multiple_of = pad_to_multiple_of

    def __call__(self, records: list[Record]) -> dict[str, torch.Tensor]:
        encoded = self.tokenizer(
            [record.premise for record in records],
            [record.hypothesis for record in records],
            padding=True,
            truncation=True,
            max_length=self.max_length,
            pad_to_multiple_of=self.pad_to_multiple_of,
            return_tensors="pt",
        )
        encoded["labels"] = torch.tensor([record.label for record in records], dtype=torch.long)
        return encoded


class LengthGroupedBatchSampler:
    """Deterministic length buckets with shuffled batch order each epoch."""

    def __init__(self, dataset: MNLIDataset, batch_size: int, seed: int):
        ordered = sorted(
            range(len(dataset)),
            key=lambda index: len(dataset[index].premise) + len(dataset[index].hypothesis),
        )
        self.batches = [ordered[start : start + batch_size] for start in range(0, len(ordered), batch_size)]
        self.seed = seed
        self.epoch = 0

    def set_epoch(self, epoch: int) -> None:
        self.epoch = epoch

    def __iter__(self):
        order = list(range(len(self.batches)))
        random.Random(self.seed + self.epoch).shuffle(order)
        for index in order:
            yield self.batches[index]

    def __len__(self) -> int:
        return len(self.batches)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, default=SCRIPT_DIR / "build" / "plue" / "MNLI")
    parser.add_argument("--output-dir", type=Path, default=SCRIPT_DIR / "build" / "training")
    parser.add_argument("--model-id", default=MODEL_ID)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--gradient-accumulation", type=int, default=2)
    parser.add_argument("--max-length", type=int, default=256)
    parser.add_argument("--learning-rate", type=float, default=2e-5)
    parser.add_argument("--weight-decay", type=float, default=0.01)
    parser.add_argument("--warmup-ratio", type=float, default=0.10)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--max-train-samples", type=int)
    parser.add_argument("--max-eval-samples", type=int)
    parser.add_argument("--max-steps", type=int)
    parser.add_argument("--log-every", type=int, default=50)
    parser.add_argument(
        "--pad-to-multiple-of",
        type=int,
        help="Bound dynamic MPS shapes by rounding batch padding (for example, 32)",
    )
    parser.add_argument(
        "--mps-empty-cache-every",
        type=int,
        default=0,
        help="Release unused MPS cache every N optimizer updates; 0 disables it",
    )
    parser.add_argument("--group-by-length", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--device", choices=("auto", "cuda", "mps", "cpu"), default="auto")
    parser.add_argument("--precision", choices=("auto", "fp32", "fp16", "bf16"), default="auto")
    return parser.parse_args()


def choose_device(requested: str) -> torch.device:
    if requested == "auto":
        if torch.cuda.is_available():
            return torch.device("cuda")
        if torch.backends.mps.is_available():
            return torch.device("mps")
        return torch.device("cpu")
    if requested == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA requested but is not available")
    if requested == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("MPS requested but is not available")
    return torch.device(requested)


def seed_everything(seed: int) -> None:
    random.seed(seed)
    os.environ["PYTHONHASHSEED"] = str(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def choose_precision(requested: str, device: torch.device) -> str:
    if requested != "auto":
        if requested != "fp32" and device.type == "cpu":
            raise ValueError("fp16/bf16 training is not enabled for CPU in this spike")
        if requested != "fp32" and device.type == "mps":
            raise ValueError("MPS mixed-precision GradScaler is unsupported here; use fp32")
        return requested
    if device.type == "mps":
        return "fp32"
    if device.type == "cuda":
        return "bf16" if torch.cuda.is_bf16_supported() else "fp16"
    return "fp32"


def autocast_context(device: torch.device, precision: str):
    if precision == "fp32":
        return nullcontext()
    dtype = torch.float16 if precision == "fp16" else torch.bfloat16
    return torch.autocast(device_type=device.type, dtype=dtype)


def sync(device: torch.device) -> None:
    if device.type == "cuda":
        torch.cuda.synchronize()
    elif device.type == "mps":
        torch.mps.synchronize()


def accelerator_memory(device: torch.device) -> dict[str, float]:
    if device.type == "mps":
        return {
            "allocated_mb": torch.mps.current_allocated_memory() / 1024 / 1024,
            "driver_mb": torch.mps.driver_allocated_memory() / 1024 / 1024,
        }
    if device.type == "cuda":
        return {
            "allocated_mb": torch.cuda.memory_allocated() / 1024 / 1024,
            "driver_mb": torch.cuda.memory_reserved() / 1024 / 1024,
        }
    return {}


def to_device(batch: dict[str, torch.Tensor], device: torch.device) -> dict[str, torch.Tensor]:
    return {name: tensor.to(device) for name, tensor in batch.items()}


def metrics_from_confusion(confusion: list[list[int]], loss: float) -> dict[str, Any]:
    total = sum(sum(row) for row in confusion)
    correct = sum(confusion[index][index] for index in range(3))
    per_class: dict[str, dict[str, float | int]] = {}
    f1_values: list[float] = []
    for label_id in range(3):
        true_positive = confusion[label_id][label_id]
        false_positive = sum(confusion[row][label_id] for row in range(3) if row != label_id)
        false_negative = sum(confusion[label_id][column] for column in range(3) if column != label_id)
        precision = true_positive / (true_positive + false_positive) if true_positive + false_positive else 0.0
        recall = true_positive / (true_positive + false_negative) if true_positive + false_negative else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
        support = sum(confusion[label_id])
        f1_values.append(f1)
        per_class[ID2LABEL[label_id]] = {
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "support": support,
        }
    return {
        "loss": loss,
        "accuracy": correct / total if total else 0.0,
        "macro_f1": sum(f1_values) / len(f1_values),
        "confusion_rows_true_columns_predicted": confusion,
        "per_class": per_class,
        "examples": total,
    }


@torch.inference_mode()
def evaluate(
    model: torch.nn.Module,
    loader: DataLoader,
    device: torch.device,
    precision: str,
) -> dict[str, Any]:
    model.eval()
    confusion = [[0, 0, 0] for _ in range(3)]
    weighted_loss = 0.0
    examples = 0
    started = time.perf_counter()
    for batch in loader:
        batch = to_device(batch, device)
        with autocast_context(device, precision):
            output = model(**batch)
        labels = batch["labels"]
        predictions = output.logits.argmax(dim=-1)
        batch_size = labels.shape[0]
        weighted_loss += float(output.loss.detach().cpu()) * batch_size
        examples += batch_size
        for truth, prediction in zip(labels.detach().cpu().tolist(), predictions.detach().cpu().tolist()):
            confusion[truth][prediction] += 1
    sync(device)
    result = metrics_from_confusion(confusion, weighted_loss / examples)
    elapsed = time.perf_counter() - started
    result["elapsed_seconds"] = elapsed
    result["examples_per_second"] = examples / elapsed
    return result


def file_md5(path: Path) -> str:
    hasher = hashlib.md5()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def save_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    if args.epochs < 1 or args.batch_size < 1 or args.gradient_accumulation < 1:
        raise ValueError("epochs, batch size, and gradient accumulation must be positive")
    if args.pad_to_multiple_of is not None:
        if args.pad_to_multiple_of < 1 or args.max_length % args.pad_to_multiple_of != 0:
            raise ValueError("pad-to-multiple-of must be positive and divide max-length")
    if args.mps_empty_cache_every < 0:
        raise ValueError("mps-empty-cache-every cannot be negative")
    seed_everything(args.seed)
    torch.set_float32_matmul_precision("high")
    device = choose_device(args.device)
    precision = choose_precision(args.precision, device)
    train_path = args.data_dir / "train.tsv"
    eval_path = args.data_dir / "dev_matched.tsv"
    if not train_path.exists() or not eval_path.exists():
        raise FileNotFoundError("PLUE files missing; run prepare_plue.py first")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Loading PLUE from {args.data_dir}", flush=True)
    train_data = MNLIDataset(train_path, args.max_train_samples, args.seed)
    eval_data = MNLIDataset(eval_path, args.max_eval_samples, args.seed + 1)
    print(
        f"train={len(train_data):,} eval={len(eval_data):,} device={device} precision={precision} "
        f"batch={args.batch_size} accumulation={args.gradient_accumulation}",
        flush=True,
    )

    tokenizer = AutoTokenizer.from_pretrained(args.model_id, use_fast=True)
    model = AutoModelForSequenceClassification.from_pretrained(
        args.model_id,
        num_labels=3,
        id2label=ID2LABEL,
        label2id=LABEL2ID,
        ignore_mismatched_sizes=True,
    )
    model.to(device)
    collator = PairCollator(tokenizer, args.max_length, args.pad_to_multiple_of)
    length_sampler = None
    if args.group_by_length:
        length_sampler = LengthGroupedBatchSampler(train_data, args.batch_size, args.seed)
        train_loader = DataLoader(
            train_data,
            batch_sampler=length_sampler,
            collate_fn=collator,
            num_workers=0,
            pin_memory=device.type == "cuda",
        )
    else:
        generator = torch.Generator().manual_seed(args.seed)
        train_loader = DataLoader(
            train_data,
            batch_size=args.batch_size,
            shuffle=True,
            generator=generator,
            collate_fn=collator,
            num_workers=0,
            pin_memory=device.type == "cuda",
        )
    eval_loader = DataLoader(
        eval_data,
        batch_size=args.batch_size,
        shuffle=False,
        collate_fn=collator,
        num_workers=0,
        pin_memory=device.type == "cuda",
    )

    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate, weight_decay=args.weight_decay)
    scaler = torch.amp.GradScaler(device.type, enabled=precision == "fp16")
    updates_per_epoch = math.ceil(len(train_loader) / args.gradient_accumulation)
    planned_updates = updates_per_epoch * args.epochs
    if args.max_steps is not None:
        planned_updates = min(planned_updates, args.max_steps)
    warmup_steps = round(planned_updates * args.warmup_ratio)
    scheduler = get_linear_schedule_with_warmup(optimizer, warmup_steps, planned_updates)

    manifest = {
        "model_id": args.model_id,
        "dataset": "PLUE/MNLI",
        "train_md5": file_md5(train_path),
        "label_order_used_for_training": ID2LABEL,
        "selection_metric": "highest PLUE dev_matched macro_f1; eval_loss breaks ties",
        "adversarial_set_used_for_selection": False,
        "hparams": {
            "epochs": args.epochs,
            "batch_size": args.batch_size,
            "gradient_accumulation": args.gradient_accumulation,
            "effective_batch_size": args.batch_size * args.gradient_accumulation,
            "max_length": args.max_length,
            "learning_rate": args.learning_rate,
            "weight_decay": args.weight_decay,
            "warmup_ratio": args.warmup_ratio,
            "seed": args.seed,
            "max_train_samples": args.max_train_samples,
            "max_eval_samples": args.max_eval_samples,
            "max_steps": args.max_steps,
            "group_by_length": args.group_by_length,
            "pad_to_multiple_of": args.pad_to_multiple_of,
            "mps_empty_cache_every": args.mps_empty_cache_every,
        },
        "runtime": {
            "device": str(device),
            "precision": precision,
            "torch": torch.__version__,
            "transformers": __import__("transformers").__version__,
            "python": sys.version,
            "platform": platform.platform(),
        },
        "counts": {
            "train": len(train_data),
            "eval": len(eval_data),
            "train_valid_before_sample_limit": train_data.source_valid_records,
            "eval_valid_before_sample_limit": eval_data.source_valid_records,
            "train_rows_excluded_for_empty_text": train_data.skipped_empty,
            "eval_rows_excluded_for_empty_text": eval_data.skipped_empty,
            "train_labels": dict(sorted(Counter(ID2LABEL[item.label] for item in train_data.records).items())),
            "eval_labels": dict(sorted(Counter(ID2LABEL[item.label] for item in eval_data.records).items())),
            "planned_optimizer_updates": planned_updates,
            "warmup_steps": warmup_steps,
        },
    }
    save_json(args.output_dir / "training_manifest.json", manifest)

    best: dict[str, Any] | None = None
    global_update = 0
    consumed_examples = 0
    training_started = time.perf_counter()
    stop = False
    memory_samples: list[dict[str, float | int]] = []
    optimizer.zero_grad(set_to_none=True)

    for epoch in range(1, args.epochs + 1):
        if length_sampler is not None:
            length_sampler.set_epoch(epoch)
        model.train()
        running_loss = 0.0
        interval_started = time.perf_counter()
        interval_examples = 0
        for batch_index, batch in enumerate(train_loader, start=1):
            batch = to_device(batch, device)
            with autocast_context(device, precision):
                output = model(**batch)
                loss = output.loss / args.gradient_accumulation
            scaler.scale(loss).backward()
            running_loss += float(output.loss.detach().cpu())
            batch_examples = batch["labels"].shape[0]
            consumed_examples += batch_examples
            interval_examples += batch_examples

            is_update = batch_index % args.gradient_accumulation == 0 or batch_index == len(train_loader)
            if not is_update:
                continue
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            scaler.step(optimizer)
            scaler.update()
            scheduler.step()
            optimizer.zero_grad(set_to_none=True)
            global_update += 1

            if (
                device.type == "mps"
                and args.mps_empty_cache_every
                and global_update % args.mps_empty_cache_every == 0
            ):
                sync(device)
                torch.mps.empty_cache()

            if global_update == 1 or global_update % args.log_every == 0:
                sync(device)
                elapsed = time.perf_counter() - interval_started
                memory = accelerator_memory(device)
                memory_samples.append({"update": global_update, **memory})
                memory_text = "" if not memory else (
                    f" allocated_mb={memory['allocated_mb']:.1f} driver_mb={memory['driver_mb']:.1f}"
                )
                print(
                    f"epoch={epoch} update={global_update}/{planned_updates} "
                    f"loss={running_loss / batch_index:.4f} "
                    f"examples/s={interval_examples / elapsed:.2f} "
                    f"lr={scheduler.get_last_lr()[0]:.3e}{memory_text}",
                    flush=True,
                )
                interval_started = time.perf_counter()
                interval_examples = 0

            if args.max_steps is not None and global_update >= args.max_steps:
                stop = True
                break

        validation = evaluate(model, eval_loader, device, precision)
        validation.update({"epoch": epoch, "global_update": global_update})
        save_json(args.output_dir / f"epoch_{epoch}_metrics.json", validation)
        print(
            f"validation epoch={epoch} macro_f1={validation['macro_f1']:.4f} "
            f"accuracy={validation['accuracy']:.4f} loss={validation['loss']:.4f}",
            flush=True,
        )

        is_better = best is None or validation["macro_f1"] > best["macro_f1"] + 1e-12
        if best is not None and abs(validation["macro_f1"] - best["macro_f1"]) <= 1e-12:
            is_better = validation["loss"] < best["loss"]
        if is_better:
            best = validation
            checkpoint = args.output_dir / "checkpoint-best"
            model.save_pretrained(checkpoint)
            tokenizer.save_pretrained(checkpoint)
            save_json(checkpoint / "selection.json", best)
            print(f"Saved selected checkpoint to {checkpoint}", flush=True)
        if stop:
            break

    sync(device)
    elapsed = time.perf_counter() - training_started
    summary = {
        "status": "COMPLETE",
        "best_validation": best,
        "optimizer_updates": global_update,
        "training_examples_seen": consumed_examples,
        "elapsed_seconds": elapsed,
        "average_examples_per_second": consumed_examples / elapsed,
        "selected_checkpoint": str(args.output_dir / "checkpoint-best"),
        "accelerator_memory_samples": memory_samples,
    }
    save_json(args.output_dir / "training_summary.json", summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
