#!/usr/bin/env python3
"""Retreino local do NLI do Verificador (BERTimbau-base, três classes) — v2.

Parte de ``neuralmind/bert-base-portuguese-cased`` (o checkpoint PyTorch do
Spike 9 está perdido) e treina com:

- PLUE/MNLI (mesmo release e hashes do Spike 9);
- subconjuntos ``pt_*`` de ``MoritzLaurer/multilingual-NLI-26lang-2mil7``
  (MNLI, FEVER-NLI, ANLI, LingNLI, WANLI), numa revisão fixa do Hub;
- opcionalmente, um JSONL "silver" (rótulos de um LLM local) com peso de loss
  configurável (``--silver``/``--silver-weight``).

Garantias:

- ordem de rótulos 0 entailment, 1 neutral, 2 contradiction (a mesma do app);
- qualquer par cujo premissa/hipótese coincida (após normalização) com textos de
  ``data/known_regressions.jsonl`` ou ``data/dev_claims.jsonl`` é excluído de
  treino, dev e hold-out; textos protegidos longos também são procurados como
  substring;
- seed fixa, seleção por macro-F1 no PLUE ``dev_matched`` (o loss desempata),
  hold-out do 2mil7 reportado mas fora da seleção (por padrão);
- estado retomável (``--resume``) salvo a cada ``--save-every`` updates, ao fim
  de cada época e ao receber SIGINT/SIGTERM;
- SHA-256 de todos os arquivos de entrada e digests dos conjuntos finais no
  manifesto e no log.

Ver ``evaluation/nli_v2/README.md`` para comandos, tempo e disco.
Este script valida e prepara os dados antes de importar PyTorch.
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
import re
import signal
import sys
import time
import unicodedata
import urllib.request
import zipfile
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable


LABELS = ("entailment", "neutral", "contradiction")
LABEL2ID = {name: index for index, name in enumerate(LABELS)}
ID2LABEL = {index: name for index, name in enumerate(LABELS)}

EVAL_DIR = Path(__file__).resolve().parent
NLI_V2_DIR = EVAL_DIR / "nli_v2"
DEFAULT_DATA_DIR = NLI_V2_DIR / "build" / "data"
DEFAULT_OUTPUT_DIR = NLI_V2_DIR / "build" / "train"
DEFAULT_PROTECTED = (
    EVAL_DIR / "data" / "known_regressions.jsonl",
    EVAL_DIR / "data" / "dev_claims.jsonl",
)

MODEL_ID = "neuralmind/bert-base-portuguese-cased"
# Commit de ``main`` no Hub (o mesmo presente no cache local usado no Spike 9).
MODEL_REVISION = "94d69c95f98f7d5b2a8700c420230ae10def0baa"
MODEL_VERSION = "bertimbau-base-nli-v2"

PLUE_URL = "https://github.com/ju-resplande/PLUE/releases/download/v1.0.0/MNLI.zip"
PLUE_ZIP_SHA256 = "20c9d4ef02743d2143e91ae52c68d4d9f3db90ab90b5835cb523b3878f5a5845"
PLUE_TRAIN_MD5 = "df6dbc8cb3e3c76f6985fd0d327f01aa"
PLUE_DEV_MD5 = "dfb55ab19b1e0bec5f048681d92b91ad"

M2_REPO = "MoritzLaurer/multilingual-NLI-26lang-2mil7"
M2_REVISION = "510a233972a0d7ff0f767d82f46e046832c10538"
# subset -> (arquivo no repo, SHA-256 esperado). Os hashes conferem com o oid
# LFS publicado no Hub para esta revisão.
M2_FILES = {
    "mnli": ("data/pt_mnli-00000-of-00001-26d159c0e0093c80.parquet",
             "8afc9d99033b6dd4f3a59e7a4b5f6de3e5a0d14fd97a61ed88a9b850ea139dd3"),
    "fever": ("data/pt_fever-00000-of-00001-18425098adde5e44.parquet",
             "c3d383aa633e58db2e02d7355350be452b7cd73314c7c97acc50b21ac3b121ee"),
    "anli": ("data/pt_anli-00000-of-00001-21ca95ba4e8fa69b.parquet",
             "f3c04c0baabd20ce4e0d68b65fab90d873e7dcda553dab0724ffcaa1553e1b3d"),
    "ling": ("data/pt_ling-00000-of-00001-a83548f81f2eb070.parquet",
             "7b483266178dcf8067edf68aa561a05934254ea87ab56a8dce78e5d53e78af2c"),
    "wanli": ("data/pt_wanli-00000-of-00001-4fb59a850c005dea.parquet",
             "cbbc90da02b551df2890d44212ec7f3fdb43b8cf592f3aa30fc0f781a2195cf4"),
}

# Referência medida no Spike 9 (mesmo Mac, mesmos hiperparâmetros, só PLUE).
SPIKE9_SECONDS = 23_333.10
SPIKE9_TRAIN_PAIRS = 392_662
PROTECTED_SUBSTRING_MIN_CHARS = 40


# ---------------------------------------------------------------------------
# Utilidades sem PyTorch
# ---------------------------------------------------------------------------


class Tee:
    """Escreve no stdout e em ``train.log``."""

    def __init__(self, path: Path | None = None):
        self.handle = None
        if path is not None:
            path.parent.mkdir(parents=True, exist_ok=True)
            self.handle = path.open("a", encoding="utf-8")

    def __call__(self, message: str) -> None:
        line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}"
        print(line, flush=True)
        if self.handle:
            self.handle.write(line + "\n")
            self.handle.flush()


log = Tee()


def file_digest(path: Path, algorithm: str = "sha256") -> str:
    hasher = hashlib.new(algorithm)
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def save_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


_TRIM = " \t\n.!?;:,\"'“”‘’«»()[]"


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKC", text).casefold()
    text = re.sub(r"\s+", " ", text)
    return text.strip(_TRIM)


def pair_key(premise: str, hypothesis: str) -> str:
    return normalize(premise) + "\x00" + normalize(hypothesis)


@dataclass(frozen=True)
class Example:
    premise: str
    hypothesis: str
    label: int
    source: str
    weight: float = 1.0


def digest_examples(examples: Iterable[Example]) -> str:
    hasher = hashlib.sha256()
    for example in examples:
        hasher.update(
            json.dumps(
                [example.premise, example.hypothesis, example.label, example.source, example.weight],
                ensure_ascii=False,
            ).encode("utf-8")
        )
        hasher.update(b"\n")
    return hasher.hexdigest()


def label_counts(examples: Iterable[Example]) -> dict[str, dict[str, int]]:
    counts: dict[str, Counter[str]] = {}
    for example in examples:
        counts.setdefault(example.source, Counter())[ID2LABEL[example.label]] += 1
    return {source: dict(sorted(counter.items())) for source, counter in sorted(counts.items())}


def download(url: str, destination: Path) -> None:
    if destination.exists():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".partial")
    log(f"download {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "nli-v2-local-training/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as output:
        while True:
            block = response.read(1024 * 1024)
            if not block:
                break
            output.write(block)
    os.replace(partial, destination)


# ---------------------------------------------------------------------------
# Dados
# ---------------------------------------------------------------------------


def prepare_plue(data_dir: Path) -> dict[str, Any]:
    plue_dir = data_dir / "plue"
    archive = plue_dir / "MNLI.zip"
    files = {"train.tsv": PLUE_TRAIN_MD5, "dev_matched.tsv": PLUE_DEV_MD5}
    if not all((plue_dir / name).exists() for name in files):
        download(PLUE_URL, archive)
        observed = file_digest(archive)
        if observed != PLUE_ZIP_SHA256:
            raise RuntimeError(f"MNLI.zip SHA-256 {observed} != {PLUE_ZIP_SHA256}")
        with zipfile.ZipFile(archive) as bundle:
            for name in files:
                members = [item for item in bundle.namelist() if Path(item).name == name]
                if len(members) != 1:
                    raise RuntimeError(f"{name}: esperado 1 membro, achei {members}")
                (plue_dir / name).write_bytes(bundle.read(members[0]))
        # O ZIP (113 MiB) não é mais necessário; os TSVs têm MD5 publicado.
        archive.unlink()
    report: dict[str, Any] = {"url": PLUE_URL, "zip_sha256": PLUE_ZIP_SHA256}
    for name, expected_md5 in files.items():
        path = plue_dir / name
        md5 = file_digest(path, "md5")
        if md5 != expected_md5:
            raise RuntimeError(f"{name}: MD5 {md5} != {expected_md5}")
        report[name] = {"md5": md5, "sha256": file_digest(path), "bytes": path.stat().st_size}
    return report


def prepare_m2(data_dir: Path, subsets: list[str]) -> dict[str, Any]:
    m2_dir = data_dir / "m2"
    report: dict[str, Any] = {"repo": M2_REPO, "revision": M2_REVISION, "files": {}}
    for subset in subsets:
        remote, expected = M2_FILES[subset]
        path = m2_dir / Path(remote).name
        url = f"https://huggingface.co/datasets/{M2_REPO}/resolve/{M2_REVISION}/{remote}"
        download(url, path)
        sha = file_digest(path)
        if expected and sha != expected:
            raise RuntimeError(f"{path.name}: SHA-256 {sha} != {expected}")
        report["files"][subset] = {"path": remote, "sha256": sha, "bytes": path.stat().st_size}
    return report


def read_plue(path: Path, source: str) -> tuple[list[Example], dict[str, int]]:
    examples: list[Example] = []
    skipped = Counter()
    with path.open("r", encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            label = (row.get("gold_label") or "").strip()
            premise = (row.get("sentence1") or "").strip()
            hypothesis = (row.get("sentence2") or "").strip()
            if label not in LABEL2ID:
                skipped["invalid_label"] += 1
            elif not premise or not hypothesis:
                skipped["empty_text"] += 1
            else:
                examples.append(Example(premise, hypothesis, LABEL2ID[label], source))
    return examples, dict(skipped)


def read_m2(path: Path, subset: str) -> tuple[list[tuple[Example, str]], dict[str, int]]:
    import pyarrow.parquet as pq

    table = pq.read_table(path, columns=["premise", "hypothesis", "label", "premise_original"])
    rows = table.to_pylist()
    examples: list[tuple[Example, str]] = []
    skipped = Counter()
    for row in rows:
        premise = (row.get("premise") or "").strip()
        hypothesis = (row.get("hypothesis") or "").strip()
        label = row.get("label")
        if label not in (0, 1, 2):
            skipped["invalid_label"] += 1
            continue
        if not premise or not hypothesis:
            skipped["empty_text"] += 1
            continue
        group = normalize(row.get("premise_original") or premise)
        examples.append((Example(premise, hypothesis, int(label), f"m2_{subset}"), group))
    return examples, dict(skipped)


def read_silver(path: Path, weight: float) -> tuple[list[Example], dict[str, int]]:
    examples: list[Example] = []
    skipped = Counter()
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                skipped["invalid_json"] += 1
                continue
            label = row.get("label")
            if isinstance(label, str):
                label = LABEL2ID.get(label.strip().lower())
            premise = str(row.get("premise") or "").strip()
            hypothesis = str(row.get("hypothesis") or "").strip()
            if label not in (0, 1, 2):
                skipped["invalid_label"] += 1
            elif not premise or not hypothesis:
                skipped["empty_text"] += 1
            else:
                examples.append(Example(premise, hypothesis, int(label), "silver", weight))
    return examples, dict(skipped)


def load_protected(paths: list[Path]) -> tuple[set[str], list[str], dict[str, Any]]:
    """Textos (premissa, hipótese, claim, trechos) que nunca podem ser treinados."""

    keys = {"premise", "hypothesis", "claim", "text", "sentence1", "sentence2"}
    exact: set[str] = set()
    report: dict[str, Any] = {}

    def walk(value: Any) -> Iterable[str]:
        if isinstance(value, dict):
            for key, item in value.items():
                if key in keys and isinstance(item, str):
                    yield item
                else:
                    yield from walk(item)
        elif isinstance(value, list):
            for item in value:
                yield from walk(item)

    for path in paths:
        if not path.exists():
            report[str(path)] = {"present": False}
            continue
        texts = 0
        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                if line.strip():
                    for text in walk(json.loads(line)):
                        normalized = normalize(text)
                        if normalized:
                            exact.add(normalized)
                            texts += 1
        report[str(path)] = {"present": True, "sha256": file_digest(path), "texts": texts}
    long_texts = sorted(text for text in exact if len(text) >= PROTECTED_SUBSTRING_MIN_CHARS)
    return exact, long_texts, report


def is_protected(example: Example, exact: set[str], long_texts: list[str]) -> bool:
    premise = normalize(example.premise)
    hypothesis = normalize(example.hypothesis)
    if premise in exact or hypothesis in exact:
        return True
    return any(text in premise or text in hypothesis for text in long_texts)


def split_heldout(
    rows: list[tuple[Example, str]], per_source: int, seed: int
) -> tuple[list[tuple[Example, str]], list[tuple[Example, str]]]:
    """Separa grupos inteiros (mesma premissa original) para hold-out."""

    if per_source <= 0:
        return rows, []
    groups: dict[str, int] = Counter(group for _, group in rows)
    source = rows[0][0].source if rows else ""
    ranked = sorted(groups, key=lambda group: hashlib.blake2b(f"{seed}:{source}:{group}".encode()).hexdigest())
    chosen: set[str] = set()
    total = 0
    for group in ranked:
        if total >= per_source:
            break
        chosen.add(group)
        total += groups[group]
    train = [row for row in rows if row[1] not in chosen]
    heldout = [row for row in rows if row[1] in chosen]
    return train, heldout


def build_datasets(args: argparse.Namespace) -> dict[str, Any]:
    data_dir: Path = args.data_dir
    subsets = args.m2_subsets
    sources_report = {"plue": prepare_plue(data_dir), "m2": prepare_m2(data_dir, subsets) if subsets else None}
    exact, long_texts, protected_report = load_protected(args.protected)
    log(f"textos protegidos: {len(exact)} (substring >= {PROTECTED_SUBSTRING_MIN_CHARS} chars: {len(long_texts)})")

    stats: dict[str, Any] = {"skipped": {}, "excluded_protected": Counter(), "excluded_dedup": Counter()}

    plue_train, stats["skipped"]["plue_mnli_train"] = read_plue(data_dir / "plue" / "train.tsv", "plue_mnli")
    dev, stats["skipped"]["plue_dev_matched"] = read_plue(data_dir / "plue" / "dev_matched.tsv", "plue_dev_matched")

    m2_train: list[Example] = []
    heldout: list[Example] = []
    for subset in subsets:
        rows, stats["skipped"][f"m2_{subset}"] = read_m2(data_dir / "m2" / Path(M2_FILES[subset][0]).name, subset)
        # pt_mnli vem do MNLI train, que o PLUE contém inteiro (outra tradução):
        # um hold-out dele vazaria. Hold-out só de FEVER/ANLI/LingNLI/WANLI.
        per_source = 0 if subset == "mnli" else args.heldout_per_source
        train_rows, heldout_rows = split_heldout(rows, per_source, args.seed)
        m2_train.extend(example for example, _ in train_rows)
        heldout.extend(example for example, _ in heldout_rows)

    silver: list[Example] = []
    if args.silver is not None:
        if not args.silver.exists():
            raise FileNotFoundError(f"--silver {args.silver} não existe")
        silver, stats["skipped"]["silver"] = read_silver(args.silver, args.silver_weight)
        sources_report["silver"] = {
            "path": str(args.silver),
            "sha256": file_digest(args.silver),
            "weight": args.silver_weight,
        }

    def drop_protected(examples: list[Example], split: str) -> list[Example]:
        kept = []
        for example in examples:
            if is_protected(example, exact, long_texts):
                stats["excluded_protected"][f"{split}:{example.source}"] += 1
            else:
                kept.append(example)
        return kept

    dev = drop_protected(dev, "dev")
    heldout = drop_protected(heldout, "heldout")
    candidates = drop_protected(plue_train + m2_train + silver, "train")

    # Sem vazamento: nenhum par/premissa do dev ou do hold-out no treino.
    blocked_pairs = {pair_key(item.premise, item.hypothesis) for item in dev + heldout}
    blocked_premises = {normalize(item.premise) for item in dev + heldout}
    by_key: dict[str, list[Example]] = {}
    order: list[str] = []
    for example in candidates:
        key = pair_key(example.premise, example.hypothesis)
        if key in blocked_pairs or normalize(example.premise) in blocked_premises:
            stats["excluded_dedup"][f"eval_overlap:{example.source}"] += 1
            continue
        if key not in by_key:
            by_key[key] = []
            order.append(key)
        by_key[key].append(example)
    train: list[Example] = []
    for key in order:
        copies = by_key[key]
        gold_labels = {item.label for item in copies if item.source != "silver"}
        if len(gold_labels) > 1:
            for item in copies:
                stats["excluded_dedup"][f"conflicting_label:{item.source}"] += 1
            continue
        if gold_labels:
            kept = next(item for item in copies if item.source != "silver")
        else:
            silver_labels = {item.label for item in copies}
            if len(silver_labels) > 1:
                for item in copies:
                    stats["excluded_dedup"][f"conflicting_label:{item.source}"] += 1
                continue
            kept = copies[0]
        for item in copies:
            if item is not kept:
                stats["excluded_dedup"][f"duplicate:{item.source}"] += 1
        train.append(kept)
    if args.silver is not None and args.silver_weight <= 0:
        train = [item for item in train if item.source != "silver"]

    before_limit = len(train)
    if args.max_train_samples is not None and args.max_train_samples < len(train):
        chosen = sorted(random.Random(args.seed).sample(range(len(train)), args.max_train_samples))
        train = [train[index] for index in chosen]
    if args.max_eval_samples is not None and args.max_eval_samples < len(dev):
        chosen = sorted(random.Random(args.seed + 1).sample(range(len(dev)), args.max_eval_samples))
        dev = [dev[index] for index in chosen]
    if args.max_eval_samples is not None and args.max_eval_samples < len(heldout):
        chosen = sorted(random.Random(args.seed + 2).sample(range(len(heldout)), args.max_eval_samples))
        heldout = [heldout[index] for index in chosen]

    if not train or not dev:
        raise RuntimeError("Treino ou dev vazio após filtros")
    stats["excluded_protected"] = dict(sorted(stats["excluded_protected"].items()))
    stats["excluded_dedup"] = dict(sorted(stats["excluded_dedup"].items()))
    return {
        "train": train,
        "dev": dev,
        "heldout": heldout,
        "report": {
            "sources": sources_report,
            "protected": protected_report,
            "filters": stats,
            "counts": {
                "train_before_sample_limit": before_limit,
                "train": len(train),
                "dev": len(dev),
                "heldout": len(heldout),
                "train_labels": label_counts(train),
                "dev_labels": label_counts(dev),
                "heldout_labels": label_counts(heldout),
            },
            "digests": {
                "train": digest_examples(train),
                "dev": digest_examples(dev),
                "heldout": digest_examples(heldout),
            },
        },
    }


def token_length_estimate(train: list[Example], tokenizer: Any, args: argparse.Namespace) -> dict[str, Any]:
    """Tokens com padding efetivo do treino (mesmo agrupamento do sampler)."""

    lengths: list[int] = []
    for start in range(0, len(train), 4096):
        chunk = train[start : start + 4096]
        encoded = tokenizer(
            [item.premise for item in chunk],
            [item.hypothesis for item in chunk],
            truncation=True,
            max_length=args.max_length,
        )
        lengths.extend(len(ids) for ids in encoded["input_ids"])
    ordered = sorted(range(len(train)), key=lambda index: len(train[index].premise) + len(train[index].hypothesis))
    multiple = args.pad_to_multiple_of or 1
    padded_tokens = 0
    for start in range(0, len(ordered), args.batch_size):
        batch = ordered[start : start + args.batch_size]
        longest = max(lengths[index] for index in batch)
        padded = min(args.max_length, math.ceil(longest / multiple) * multiple)
        padded_tokens += padded * len(batch)
    per_source: dict[str, list[int]] = {}
    for item, length in zip(train, lengths):
        per_source.setdefault(item.source, []).append(length)
    return {
        "examples": len(train),
        "mean_tokens": sum(lengths) / len(lengths),
        "truncated_at_max_length": sum(1 for length in lengths if length >= args.max_length),
        "padded_tokens_per_epoch": padded_tokens,
        "mean_tokens_by_source": {
            source: sum(values) / len(values) for source, values in sorted(per_source.items())
        },
    }


# ---------------------------------------------------------------------------
# Treino (PyTorch importado só aqui)
# ---------------------------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--model-id", default=MODEL_ID)
    parser.add_argument("--model-revision", default=MODEL_REVISION)
    parser.add_argument(
        "--m2-subsets",
        nargs="*",
        default=list(M2_FILES),
        choices=list(M2_FILES),
        help="Subconjuntos pt_* do 2mil7 (padrão: todos)",
    )
    parser.add_argument("--heldout-per-source", type=int, default=1000, help="Pares do 2mil7 por fonte para hold-out")
    parser.add_argument("--silver", type=Path, help="JSONL silver (premise, hypothesis, label)")
    parser.add_argument("--silver-weight", type=float, default=0.5, help="Peso do loss dos exemplos silver")
    parser.add_argument(
        "--protected",
        type=Path,
        nargs="*",
        default=list(DEFAULT_PROTECTED),
        help="JSONL cujos textos são excluídos (padrão: known_regressions + dev_claims)",
    )
    parser.add_argument("--selection", choices=("plue", "plue+heldout"), default="plue")
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
    parser.add_argument("--save-every", type=int, default=1000, help="Salvar estado retomável a cada N updates")
    parser.add_argument("--pad-to-multiple-of", type=int, default=32)
    parser.add_argument("--mps-empty-cache-every", type=int, default=100)
    parser.add_argument("--device", choices=("auto", "mps", "cpu"), default="auto")
    parser.add_argument("--resume", action="store_true", help="Retomar de output-dir/state/train_state.pt")
    parser.add_argument("--keep-state", action="store_true", help="Não apagar o estado retomável (1,3 GB) ao concluir")
    parser.add_argument("--prepare-only", action="store_true", help="Só baixar/validar dados e gravar o manifesto")
    parser.add_argument(
        "--estimate",
        action="store_true",
        help="Com --prepare-only: tokenizar o treino e estimar tempo pelo throughput do Spike 9",
    )
    parser.add_argument("--halt-after-updates", type=int, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.epochs < 1 or args.batch_size < 1 or args.gradient_accumulation < 1:
        parser.error("epochs, batch-size e gradient-accumulation devem ser positivos")
    if args.pad_to_multiple_of and args.max_length % args.pad_to_multiple_of:
        parser.error("pad-to-multiple-of deve dividir max-length")
    args.data_dir = args.data_dir.resolve()
    args.output_dir = args.output_dir.resolve()
    args.protected = [path.resolve() for path in args.protected]
    if args.silver is not None:
        args.silver = args.silver.resolve()
    return args


def is_smoke(args: argparse.Namespace) -> bool:
    return any(
        value is not None for value in (args.max_train_samples, args.max_eval_samples, args.max_steps)
    )


def hparams(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "model_id": args.model_id,
        "model_revision": args.model_revision,
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
        "pad_to_multiple_of": args.pad_to_multiple_of,
        "m2_subsets": args.m2_subsets,
        "heldout_per_source": args.heldout_per_source,
        "silver_weight": args.silver_weight if args.silver is not None else None,
        "selection": args.selection,
        "precision": "fp32",
        "optimizer": "AdamW",
        "schedule": "linear, warm-up",
        "grad_clip": 1.0,
        "group_by_length": True,
    }


def metrics_from_confusion(confusion: list[list[int]], loss: float | None) -> dict[str, Any]:
    total = sum(sum(row) for row in confusion)
    correct = sum(confusion[index][index] for index in range(3))
    per_class: dict[str, dict[str, float | int]] = {}
    f1_values: list[float] = []
    for label in range(3):
        tp = confusion[label][label]
        fp = sum(confusion[row][label] for row in range(3) if row != label)
        fn = sum(confusion[label][column] for column in range(3) if column != label)
        precision = tp / (tp + fp) if tp + fp else 0.0
        recall = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
        f1_values.append(f1)
        per_class[ID2LABEL[label]] = {"precision": precision, "recall": recall, "f1": f1, "support": sum(confusion[label])}
    return {
        "loss": loss,
        "accuracy": correct / total if total else 0.0,
        "macro_f1": sum(f1_values) / 3,
        "confusion_rows_true_columns_predicted": confusion,
        "label_order": list(LABELS),
        "per_class": per_class,
        "examples": total,
    }


def format_confusion(confusion: list[list[int]]) -> str:
    header = "true\\pred      " + "".join(f"{name[:13]:>14}" for name in LABELS)
    rows = [header] + [
        f"{LABELS[index][:13]:<15}" + "".join(f"{value:>14}" for value in row) for index, row in enumerate(confusion)
    ]
    return "\n".join(rows)


def choose_device(requested: str):
    import torch

    if requested == "auto":
        return torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    if requested == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("MPS pedido mas indisponível")
    return torch.device(requested)


def sync(device) -> None:
    import torch

    if device.type == "mps":
        torch.mps.synchronize()


class Collator:
    def __init__(self, tokenizer: Any, max_length: int, pad_to_multiple_of: int | None):
        self.tokenizer = tokenizer
        self.max_length = max_length
        self.pad_to_multiple_of = pad_to_multiple_of

    def __call__(self, examples: list[Example]):
        import torch

        encoded = self.tokenizer(
            [item.premise for item in examples],
            [item.hypothesis for item in examples],
            padding=True,
            truncation=True,
            max_length=self.max_length,
            pad_to_multiple_of=self.pad_to_multiple_of,
            return_tensors="pt",
        )
        encoded["labels"] = torch.tensor([item.label for item in examples], dtype=torch.long)
        encoded["weights"] = torch.tensor([item.weight for item in examples], dtype=torch.float32)
        return encoded


class LengthGroupedBatchSampler:
    """Baldes determinísticos por comprimento; ordem dos baldes embaralhada por época.

    ``start`` permite retomar no meio de uma época sem tokenizar os lotes já vistos.
    """

    def __init__(self, examples: list[Example], batch_size: int, seed: int):
        ordered = sorted(range(len(examples)), key=lambda i: len(examples[i].premise) + len(examples[i].hypothesis))
        self.batches = [ordered[start : start + batch_size] for start in range(0, len(ordered), batch_size)]
        self.seed = seed
        self.epoch = 0
        self.start = 0

    def __iter__(self):
        order = list(range(len(self.batches)))
        random.Random(self.seed + self.epoch).shuffle(order)
        for index in order[self.start :]:
            yield self.batches[index]

    def __len__(self) -> int:
        return len(self.batches) - self.start


def evaluate(model, examples: list[Example], collator: Collator, batch_size: int, device) -> dict[str, Any]:
    import torch
    import torch.nn.functional as F

    model.eval()
    confusion = [[0, 0, 0] for _ in range(3)]
    loss_sum = 0.0
    started = time.perf_counter()
    with torch.inference_mode():
        for start in range(0, len(examples), batch_size):
            batch = collator(examples[start : start + batch_size])
            labels = batch.pop("labels").to(device)
            batch.pop("weights")
            logits = model(**{name: tensor.to(device) for name, tensor in batch.items()}).logits
            loss_sum += float(F.cross_entropy(logits, labels, reduction="sum").cpu())
            for truth, prediction in zip(labels.cpu().tolist(), logits.argmax(-1).cpu().tolist()):
                confusion[truth][prediction] += 1
    sync(device)
    result = metrics_from_confusion(confusion, loss_sum / max(1, len(examples)))
    result["elapsed_seconds"] = time.perf_counter() - started
    model.train()
    return result


def rng_state() -> dict[str, Any]:
    import torch

    state = {"python": random.getstate(), "torch": torch.get_rng_state()}
    if torch.backends.mps.is_available():
        state["mps"] = torch.mps.get_rng_state()
    return state


def restore_rng(state: dict[str, Any]) -> None:
    import torch

    random.setstate(state["python"])
    torch.set_rng_state(state["torch"])
    if "mps" in state and torch.backends.mps.is_available():
        torch.mps.set_rng_state(state["mps"])


def train(args: argparse.Namespace, data: dict[str, Any], manifest: dict[str, Any]) -> int:
    import torch
    import torch.nn.functional as F
    import transformers
    from torch.utils.data import DataLoader
    from transformers import AutoModelForSequenceClassification, AutoTokenizer
    from transformers.optimization import get_linear_schedule_with_warmup

    random.seed(args.seed)
    os.environ["PYTHONHASHSEED"] = str(args.seed)
    torch.manual_seed(args.seed)
    torch.set_float32_matmul_precision("high")
    device = choose_device(args.device)
    output = args.output_dir
    state_path = output / "state" / "train_state.pt"

    train_examples: list[Example] = data["train"]
    dev_examples: list[Example] = data["dev"]
    heldout_examples: list[Example] = data["heldout"]

    tokenizer = AutoTokenizer.from_pretrained(args.model_id, revision=args.model_revision, use_fast=True)
    model = AutoModelForSequenceClassification.from_pretrained(
        args.model_id,
        revision=args.model_revision,
        num_labels=3,
        id2label=ID2LABEL,
        label2id=LABEL2ID,
    )
    model.to(device)
    collator = Collator(tokenizer, args.max_length, args.pad_to_multiple_of)
    sampler = LengthGroupedBatchSampler(train_examples, args.batch_size, args.seed)
    batches_per_epoch = len(sampler.batches)
    updates_per_epoch = math.ceil(batches_per_epoch / args.gradient_accumulation)
    planned_updates = updates_per_epoch * args.epochs
    if args.max_steps is not None:
        planned_updates = min(planned_updates, args.max_steps)
    warmup = round(planned_updates * args.warmup_ratio)

    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate, weight_decay=args.weight_decay)
    scheduler = get_linear_schedule_with_warmup(optimizer, warmup, planned_updates)

    manifest["runtime"] = {
        "device": str(device),
        "torch": torch.__version__,
        "transformers": transformers.__version__,
        "python": sys.version,
        "platform": platform.platform(),
    }
    manifest["schedule"] = {
        "batches_per_epoch": batches_per_epoch,
        "updates_per_epoch": updates_per_epoch,
        "planned_optimizer_updates": planned_updates,
        "warmup_steps": warmup,
    }
    fingerprint = {"hparams": manifest["hparams"], "digests": manifest["data"]["digests"], "schedule": manifest["schedule"]}

    state: dict[str, Any] = {
        "next_epoch": 1,
        "next_batch": 0,
        "global_update": 0,
        "examples_seen": 0,
        "running_loss": 0.0,
        "running_batches": 0,
        "best": None,
        "history": [],
        "elapsed_seconds": 0.0,
        "resumes": 0,
    }
    if args.resume:
        if not state_path.exists():
            raise FileNotFoundError(f"--resume sem estado em {state_path}")
        saved = torch.load(state_path, map_location="cpu", weights_only=False)
        if saved["fingerprint"] != fingerprint:
            raise RuntimeError(
                "Estado salvo não corresponde a estes dados/hiperparâmetros; não retomo.\n"
                f"salvo={json.dumps(saved['fingerprint'], sort_keys=True)}\n"
                f"atual={json.dumps(fingerprint, sort_keys=True)}"
            )
        model.load_state_dict(saved["model"])
        optimizer.load_state_dict(saved["optimizer"])
        scheduler.load_state_dict(saved["scheduler"])
        restore_rng(saved["rng"])
        state = saved["progress"]
        state["resumes"] += 1
        log(
            f"retomando: época {state['next_epoch']} lote {state['next_batch']} "
            f"update {state['global_update']}/{planned_updates}"
        )
    elif state_path.exists():
        raise RuntimeError(f"{state_path} já existe; use --resume ou outro --output-dir")

    manifest["resumes"] = state["resumes"]
    save_json(output / "training_manifest.json", manifest)
    log(
        f"device={device} train={len(train_examples):,} dev={len(dev_examples):,} heldout={len(heldout_examples):,} "
        f"updates={planned_updates} warmup={warmup}"
    )

    stop_signal = {"received": None}

    def on_signal(signum, _frame):
        stop_signal["received"] = signal.Signals(signum).name
        log(f"{stop_signal['received']} recebido: salvando no próximo update e saindo")

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    def save_state() -> None:
        state_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = state_path.with_suffix(".tmp")
        torch.save(
            {
                "fingerprint": fingerprint,
                "model": model.state_dict(),
                "optimizer": optimizer.state_dict(),
                "scheduler": scheduler.state_dict(),
                "rng": rng_state(),
                "progress": state,
            },
            temporary,
        )
        os.replace(temporary, state_path)
        log(f"estado salvo: época {state['next_epoch']} lote {state['next_batch']} update {state['global_update']}")

    def summary(status: str) -> dict[str, Any]:
        value = {
            "status": status,
            "run_kind": "smoke" if is_smoke(args) else "full",
            "model_version": MODEL_VERSION + ("-smoke" if is_smoke(args) else ""),
            "label_order": list(LABELS),
            "best_validation": state["best"],
            "history": state["history"],
            "optimizer_updates": state["global_update"],
            "planned_optimizer_updates": planned_updates,
            "training_examples_seen": state["examples_seen"],
            "elapsed_seconds": state["elapsed_seconds"],
            "average_examples_per_second": state["examples_seen"] / state["elapsed_seconds"] if state["elapsed_seconds"] else None,
            "selected_checkpoint": str(output / "checkpoint-best"),
            "data_digests": manifest["data"]["digests"],
            "resumes": state["resumes"],
        }
        save_json(output / "training_summary.json", value)
        return value

    def end_epoch(epoch: int) -> None:
        validation = evaluate(model, dev_examples, collator, args.batch_size * 2, device)
        heldout = evaluate(model, heldout_examples, collator, args.batch_size * 2, device) if heldout_examples else None
        score = validation["macro_f1"]
        if args.selection == "plue+heldout" and heldout is not None:
            score = (validation["macro_f1"] + heldout["macro_f1"]) / 2
        record = {
            "epoch": epoch,
            "global_update": state["global_update"],
            "selection_score": score,
            "plue_dev": validation,
            "heldout_2mil7": heldout,
        }
        state["history"].append(record)
        save_json(output / f"epoch_{epoch}_metrics.json", record)
        log(
            f"validação época {epoch}: PLUE macro_f1={validation['macro_f1']:.4f} acc={validation['accuracy']:.4f} "
            f"loss={validation['loss']:.4f}"
            + (f" | hold-out 2mil7 macro_f1={heldout['macro_f1']:.4f}" if heldout else "")
            + "\n"
            + format_confusion(validation["confusion_rows_true_columns_predicted"])
        )
        best = state["best"]
        better = best is None or score > best["selection_score"] + 1e-12
        if best is not None and abs(score - best["selection_score"]) <= 1e-12:
            better = validation["loss"] < best["plue_dev"]["loss"]
        if better:
            state["best"] = record
            checkpoint = output / "checkpoint-best"
            model.save_pretrained(checkpoint)
            tokenizer.save_pretrained(checkpoint)
            save_json(checkpoint / "selection.json", record)
            log(f"checkpoint selecionado salvo em {checkpoint} (época {epoch})")

    loader_kwargs = {"collate_fn": collator, "num_workers": 0}
    model.train()
    optimizer.zero_grad(set_to_none=True)
    finished = state["global_update"] >= planned_updates
    while not finished and state["next_epoch"] <= args.epochs:
        epoch = state["next_epoch"]
        sampler.epoch = epoch
        sampler.start = state["next_batch"]
        loader = DataLoader(train_examples, batch_sampler=sampler, **loader_kwargs)
        interval_started = time.perf_counter()
        interval_examples = 0
        segment_started = time.perf_counter()
        batch_index = state["next_batch"]
        for batch in loader:
            batch_index += 1
            labels = batch.pop("labels").to(device)
            weights = batch.pop("weights").to(device)
            logits = model(**{name: tensor.to(device) for name, tensor in batch.items()}).logits
            per_example = F.cross_entropy(logits, labels, reduction="none")
            loss = (per_example * weights).sum() / labels.shape[0]
            (loss / args.gradient_accumulation).backward()
            state["running_loss"] += float(loss.detach().cpu())
            state["running_batches"] += 1
            state["examples_seen"] += labels.shape[0]
            interval_examples += labels.shape[0]

            if batch_index % args.gradient_accumulation and batch_index != batches_per_epoch:
                continue
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            scheduler.step()
            optimizer.zero_grad(set_to_none=True)
            state["global_update"] += 1
            state["next_batch"] = batch_index
            update = state["global_update"]

            if device.type == "mps" and args.mps_empty_cache_every and update % args.mps_empty_cache_every == 0:
                sync(device)
                torch.mps.empty_cache()
            if update == 1 or update % args.log_every == 0:
                sync(device)
                elapsed = time.perf_counter() - interval_started
                memory = ""
                if device.type == "mps":
                    memory = (
                        f" alloc_mb={torch.mps.current_allocated_memory() / 2**20:.0f}"
                        f" driver_mb={torch.mps.driver_allocated_memory() / 2**20:.0f}"
                    )
                log(
                    f"época={epoch} update={update}/{planned_updates} "
                    f"loss={state['running_loss'] / max(1, state['running_batches']):.4f} "
                    f"ex/s={interval_examples / elapsed:.1f} lr={scheduler.get_last_lr()[0]:.3e}{memory}"
                )
                interval_started = time.perf_counter()
                interval_examples = 0

            halt = args.halt_after_updates is not None and update >= args.halt_after_updates
            periodic = args.save_every and update % args.save_every == 0
            if update >= planned_updates:
                finished = True
                break
            if periodic or halt or stop_signal["received"]:
                state["elapsed_seconds"] += time.perf_counter() - segment_started
                segment_started = time.perf_counter()
                save_state()
                if halt or stop_signal["received"]:
                    summary("INTERRUPTED")
                    log("interrompido; retome com --resume")
                    return 3
        state["elapsed_seconds"] += time.perf_counter() - segment_started
        end_epoch(epoch)
        state["next_epoch"] = epoch + 1
        state["next_batch"] = 0
        state["running_loss"] = 0.0
        state["running_batches"] = 0
        if finished or state["next_epoch"] > args.epochs:
            break
        save_state()
        if stop_signal["received"]:
            summary("INTERRUPTED")
            return 3

    final = summary("COMPLETE")
    if state_path.exists() and not args.keep_state:
        state_path.unlink()
        log(f"estado retomável removido ({state_path}); use --keep-state para mantê-lo")
    log(
        "treino COMPLETO: "
        + json.dumps(
            {
                "model_version": final["model_version"],
                "updates": final["optimizer_updates"],
                "elapsed_seconds": round(final["elapsed_seconds"], 1),
                "best_epoch": final["best_validation"]["epoch"] if final["best_validation"] else None,
                "best_plue_macro_f1": final["best_validation"]["plue_dev"]["macro_f1"] if final["best_validation"] else None,
            },
            ensure_ascii=False,
        )
    )
    return 0


def write_jsonl(path: Path, examples: list[Example]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for item in examples:
            handle.write(json.dumps({**asdict(item), "label_name": ID2LABEL[item.label]}, ensure_ascii=False) + "\n")


def main(argv: list[str] | None = None) -> int:
    global log
    args = parse_args(argv)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    log = Tee(args.output_dir / "train.log")
    log(f"argv: {' '.join(sys.argv[1:])}")

    data = build_datasets(args)
    report = data["report"]
    manifest = {
        "model_version": MODEL_VERSION + ("-smoke" if is_smoke(args) else ""),
        "label_order_used_for_training": ID2LABEL,
        "selection_metric": (
            "maior macro-F1 no PLUE dev_matched; loss desempata"
            if args.selection == "plue"
            else "média do macro-F1 PLUE dev_matched e hold-out 2mil7; loss PLUE desempata"
        ),
        "regressions_used_for_training_or_selection": False,
        "hparams": hparams(args),
        "data": report,
    }
    log("dados: " + json.dumps(report["counts"], ensure_ascii=False))
    log("digests: " + json.dumps(report["digests"]))
    log("fontes: " + json.dumps(report["sources"], ensure_ascii=False))
    log("filtros: " + json.dumps(report["filters"], ensure_ascii=False))
    write_jsonl(args.output_dir / "heldout_2mil7.jsonl", data["heldout"])

    if args.prepare_only:
        if args.estimate:
            from transformers import AutoTokenizer

            tokenizer = AutoTokenizer.from_pretrained(args.model_id, revision=args.model_revision, use_fast=True)
            estimate = token_length_estimate(data["train"], tokenizer, args)
            plue_only = [item for item in data["train"] if item.source == "plue_mnli"]
            plue_estimate = token_length_estimate(plue_only, tokenizer, args)
            ratio = estimate["padded_tokens_per_epoch"] / plue_estimate["padded_tokens_per_epoch"]
            # O Spike 9 treinou só PLUE (392.662 pares); escala pelo volume de tokens efetivos.
            plue_scale = len(plue_only) / SPIKE9_TRAIN_PAIRS
            seconds = SPIKE9_SECONDS * ratio / plue_scale * args.epochs / 3
            manifest["estimate"] = {
                "train": estimate,
                "plue_only": plue_estimate,
                "padded_token_ratio_vs_plue": ratio,
                "estimated_training_seconds": seconds,
                "basis": "Spike 9: 23.333 s para 3 épocas PLUE no mesmo protocolo, escalado por tokens com padding",
            }
            log("estimativa: " + json.dumps(manifest["estimate"], ensure_ascii=False))
        save_json(args.output_dir / "prepare_manifest.json", manifest)
        return 0
    return train(args, data, manifest)


if __name__ == "__main__":
    sys.exit(main())
