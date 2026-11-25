#!/usr/bin/env python3
"""Avalia um checkpoint do NLI v2 (PyTorch) nas regressões conhecidas e no PLUE dev.

- ``data/known_regressions.jsonl`` (15 pares): passa se o argmax está em
  ``allowed_labels``; registra as três probabilidades. Estes pares nunca são
  teste cego e foram excluídos do treino por ``train_nli_v2.py``.
- PLUE ``dev_matched`` (9.815 pares) e, se existir, o hold-out do 2mil7 gravado
  pelo treino: matriz de confusão (linhas = real, colunas = previsto), macro-F1,
  acurácia e métricas por classe.

Ordem de rótulos: 0 entailment, 1 neutral, 2 contradiction (igual ao app). O
script confere o ``id2label`` do checkpoint, mas isso não substitui as sondas
empíricas feitas na conversão.

Uso (a partir de ``evaluation/``)::

    uv run --project nli_v2 python nli_v2/evaluate_nli_v2.py \
        --checkpoint nli_v2/build/train/checkpoint-best \
        --output nli_v2/build/train/evaluation.json
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(EVAL_DIR))

from train_nli_v2 import (  # noqa: E402
    DEFAULT_DATA_DIR,
    ID2LABEL,
    LABEL2ID,
    LABELS,
    Example,
    file_digest,
    format_confusion,
    metrics_from_confusion,
    prepare_plue,
    read_plue,
    save_json,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--regressions", type=Path, default=EVAL_DIR / "data" / "known_regressions.jsonl")
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument(
        "--heldout",
        type=Path,
        help="JSONL do hold-out 2mil7 (padrão: heldout_2mil7.jsonl ao lado do checkpoint, se existir)",
    )
    parser.add_argument("--max-dev-samples", type=int, help="Só para smoke")
    parser.add_argument("--max-length", type=int, default=512, help="512 = limite do app")
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--device", choices=("auto", "mps", "cpu"), default="auto")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    import torch
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    checkpoint = args.checkpoint.resolve()
    device = torch.device(
        "mps" if args.device in ("auto", "mps") and torch.backends.mps.is_available() else "cpu"
    )
    tokenizer = AutoTokenizer.from_pretrained(checkpoint)
    model = AutoModelForSequenceClassification.from_pretrained(checkpoint).float().eval().to(device)
    config_labels = {int(key): value for key, value in model.config.id2label.items()}
    if config_labels != ID2LABEL:
        raise RuntimeError(f"id2label do checkpoint {config_labels} != {ID2LABEL}")

    def predict(pairs: list[tuple[str, str]]) -> list[list[float]]:
        probabilities: list[list[float]] = []
        with torch.inference_mode():
            for start in range(0, len(pairs), args.batch_size):
                chunk = pairs[start : start + args.batch_size]
                encoded = tokenizer(
                    [premise for premise, _ in chunk],
                    [hypothesis for _, hypothesis in chunk],
                    padding=True,
                    truncation=True,
                    max_length=args.max_length,
                    return_tensors="pt",
                ).to(device)
                logits = model(**encoded).logits.float()
                probabilities.extend(torch.softmax(logits, dim=-1).cpu().tolist())
        return probabilities

    def score(examples: list[Example], name: str) -> dict:
        started = time.perf_counter()
        probabilities = predict([(item.premise, item.hypothesis) for item in examples])
        confusion = [[0, 0, 0] for _ in range(3)]
        nll = 0.0
        for item, probs in zip(examples, probabilities):
            confusion[item.label][max(range(3), key=probs.__getitem__)] += 1
            nll -= float(torch.log(torch.tensor(max(probs[item.label], 1e-12))))
        result = metrics_from_confusion(confusion, nll / max(1, len(examples)))
        result["elapsed_seconds"] = time.perf_counter() - started
        print(
            f"\n{name}: n={result['examples']} macro_f1={result['macro_f1']:.4f} "
            f"acc={result['accuracy']:.4f} loss={result['loss']:.4f}\n"
            + format_confusion(confusion),
            flush=True,
        )
        return result

    # --- regressões conhecidas -------------------------------------------
    rows = [json.loads(line) for line in args.regressions.read_text(encoding="utf-8").splitlines() if line.strip()]
    probabilities = predict([(row["premise"], row["hypothesis"]) for row in rows])
    regression_items = []
    print(f"Regressões conhecidas ({len(rows)} pares), ordem {list(LABELS)}:", flush=True)
    for row, probs in zip(rows, probabilities):
        allowed = row["allowed_labels"]
        unknown = set(allowed) - set(LABEL2ID)
        if unknown:
            raise RuntimeError(f"{row['id']}: rótulos inválidos {unknown}")
        predicted = ID2LABEL[max(range(3), key=probs.__getitem__)]
        passed = predicted in allowed
        regression_items.append(
            {
                "id": row["id"],
                "hypothesis": row["hypothesis"],
                "allowed_labels": allowed,
                "predicted": predicted,
                "probabilities": dict(zip(LABELS, probs)),
                "passed": passed,
            }
        )
        print(
            f"  {'PASS' if passed else 'FAIL'} {row['id']:<14} pred={predicted:<13} "
            f"allowed={','.join(allowed):<22} "
            + " ".join(f"{label[:3]}={value:.3f}" for label, value in zip(LABELS, probs)),
            flush=True,
        )
    regression_confusion = [[0, 0, 0] for _ in range(3)]
    for item in regression_items:
        # Para pares com mais de um rótulo aceito, a "classe real" é o primeiro listado.
        regression_confusion[LABEL2ID[item["allowed_labels"][0]]][LABEL2ID[item["predicted"]]] += 1
    passed_count = sum(item["passed"] for item in regression_items)
    print(f"Regressões: {passed_count}/{len(regression_items)} aceitas", flush=True)
    print("Matriz (real = primeiro rótulo aceito):\n" + format_confusion(regression_confusion), flush=True)

    # --- PLUE dev ---------------------------------------------------------
    plue_report = prepare_plue(args.data_dir.resolve())
    dev, _ = read_plue(args.data_dir.resolve() / "plue" / "dev_matched.tsv", "plue_dev_matched")
    if args.max_dev_samples is not None:
        import random

        chosen = sorted(random.Random(43).sample(range(len(dev)), min(args.max_dev_samples, len(dev))))
        dev = [dev[index] for index in chosen]
    dev_result = score(dev, "PLUE dev_matched")

    # --- hold-out 2mil7 ---------------------------------------------------
    heldout_path = args.heldout or checkpoint.parent / "heldout_2mil7.jsonl"
    heldout_result = None
    heldout_by_source = {}
    if heldout_path.exists():
        heldout = [
            Example(row["premise"], row["hypothesis"], int(row["label"]), row["source"])
            for row in map(json.loads, heldout_path.read_text(encoding="utf-8").splitlines())
        ]
        if heldout:
            heldout_result = score(heldout, "Hold-out 2mil7 (todas as fontes)")
            for source in sorted({item.source for item in heldout}):
                subset = [item for item in heldout if item.source == source]
                heldout_by_source[source] = score(subset, f"Hold-out {source}")

    report = {
        "checkpoint": str(checkpoint),
        "checkpoint_weight_sha256": {
            path.name: file_digest(path)
            for path in sorted(checkpoint.iterdir())
            if path.name in {"model.safetensors", "pytorch_model.bin"}
        },
        "label_order": list(LABELS),
        "max_length": args.max_length,
        "device": str(device),
        "known_regressions": {
            "path": str(args.regressions.resolve()),
            "sha256": file_digest(args.regressions),
            "passed": passed_count,
            "total": len(regression_items),
            "confusion_rows_first_allowed_columns_predicted": regression_confusion,
            "items": regression_items,
        },
        "plue_dev_matched": {"source": plue_report["dev_matched.tsv"], "max_samples": args.max_dev_samples, **dev_result},
        "heldout_2mil7": None
        if heldout_result is None
        else {"path": str(heldout_path), "sha256": file_digest(heldout_path), **heldout_result, "by_source": heldout_by_source},
    }
    if args.output:
        save_json(args.output.resolve(), report)
        print(f"\nRelatório: {args.output}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
