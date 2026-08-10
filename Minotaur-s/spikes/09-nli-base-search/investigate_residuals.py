#!/usr/bin/env python3
"""Diagnose residual NLI errors without changing production decisions.

Writes a reproducible JSON trace with raw logits, probabilities, class margins,
WordPiece tokenization, wording perturbations, and (when the cached embedding
model is available) cosine-ranked chunks.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import torch
from transformers import AutoModel, AutoModelForSequenceClassification, AutoTokenizer

ROOT = Path(__file__).resolve().parents[2]
CHECKPOINT = ROOT / "spikes/09-nli-base-search/build/training-full/checkpoint-best"
OUTPUT = ROOT / "spikes/09-nli-base-search/build/residual_investigation.json"
LABELS = ("entailment", "neutral", "contradiction")
EMBEDDING_ID = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"

CANCER_CASES = [
    {
        "id": "metropoles-treatment-headline",
        "source": "Metrópoles",
        "source_url": "https://www.metropoles.com/saude/tilt-no-cancer-pesquisador-brasileiro-descobre-forma-inovadora-de-tratar-a-doenca",
        "expected": "neutral",
        "premise": "Tilt no câncer: pesquisador brasileiro descobre forma inovadora de tratar a doença",
        "claims": [
            "Brasileiro encontrou cura do câncer.",
            "Brasileiro encontrou tratamento para o câncer.",
            "Brasileiro encontrou uma forma inovadora de tratar o câncer.",
            "Um pesquisador brasileiro pode ter encontrado a cura de um tipo de câncer.",
        ],
    },
    {
        "id": "fantastico-attributed-claim",
        "source": "G1/Fantástico",
        "source_url": "https://globoplay.globo.com/v/11786998/",
        "expected": "neutral",
        "premise": "Quem é Marc Abreu, médico brasileiro que diz curar Alzheimer, Parkinson e câncer nos EUA",
        "claims": [
            "Brasileiro encontrou cura do câncer.",
            "Um médico brasileiro diz curar câncer.",
            "Um médico brasileiro comprovou a cura do câncer.",
            "Um médico brasileiro afirma tratar pacientes com câncer nos EUA.",
        ],
    },
]

SHORT_CASE = {
    "id": "terra-plana-short-wording",
    "source": "BBC News Brasil",
    "source_url": "https://www.bbc.com/portuguese/geral-50886149",
    "expected": "contradiction",
    "premise": (
        "Algumas teorias da conspiração que afirmam que a Terra é plana continuam se espalhando. "
        "Estas são algumas maneiras simples de comprovar que a Terra é redonda e rebater essas "
        "ideias dos terraplanistas."
    ),
    "claims": [
        "A Terra é plana.", "A Terra é plana", "Terra plana",
        "A Terra é plana e a NASA esconde isso das pessoas.",
        "Cientistas confirmaram que a Terra é plana.",
    ],
}

ARTICLE_CHUNKS = [
    "Pesquisador brasileiro descobre forma inovadora de tratar o câncer.",
    "O estudo descreve uma técnica experimental para tratar tumores, não uma cura geral da doença.",
    "Especialistas afirmam que resultados iniciais ainda precisam de ensaios clínicos em grupos maiores.",
    "A remissão observada em um paciente não permite concluir que exista cura para todos os cânceres.",
    "O pesquisador apresentou o trabalho durante um congresso médico realizado nesta semana.",
]

ADVERSARIAL_EXTENSION = [
    {
        "id": "treatment-not-cure",
        "source": "fixture derivada da manchete do Metrópoles",
        "source_url": CANCER_CASES[0]["source_url"],
        "premise": "A equipe desenvolveu uma forma experimental de tratar a doença, ainda sem evidência de cura.",
        "hypothesis": "Brasileiro encontrou cura do câncer.",
        "expected": "contradiction",
        "justification": "A premissa distingue explicitamente tratamento de cura.",
    },
    {
        "id": "attribution-is-not-fact",
        "source": "fixture derivada da reportagem do Fantástico",
        "source_url": CANCER_CASES[1]["source_url"],
        "premise": "O médico brasileiro diz curar câncer, mas não apresentou estudos que comprovem a eficácia.",
        "hypothesis": "Brasileiro encontrou cura do câncer.",
        "expected": "neutral/contradiction",
        "justification": "Atribuição sem comprovação não acarreta a alegação factual; a ressalva admite neutral ou contradição.",
    },
    {
        "id": "single-remission",
        "source": "caso adversarial controlado, motivado pelos chunks reais",
        "source_url": CANCER_CASES[0]["source_url"],
        "premise": "Um paciente entrou em remissão após terapia criada por um pesquisador brasileiro.",
        "hypothesis": "Brasileiro encontrou cura do câncer.",
        "expected": "neutral",
        "justification": "Remissão de um paciente não implica cura geral nem causalidade estabelecida.",
    },
    {
        "id": "qualified-cure-claim",
        "source": "controle semântico",
        "source_url": CANCER_CASES[1]["source_url"],
        "premise": "Um médico brasileiro afirma ter curado alguns pacientes com câncer nos EUA.",
        "hypothesis": "Um médico brasileiro afirma ter curado alguns pacientes com câncer nos EUA.",
        "expected": "entailment",
        "justification": "Hipótese preserva atribuição e quantificador da premissa.",
    },
]


def softmax(values: list[float]) -> list[float]:
    top = max(values)
    exps = [math.exp(value - top) for value in values]
    total = sum(exps)
    return [value / total for value in exps]


@torch.inference_mode()
def trace_pair(tokenizer, model, premise: str, hypothesis: str) -> dict:
    encoded = tokenizer(premise, hypothesis, truncation=True, max_length=512, return_tensors="pt")
    logits = model(**encoded).logits[0].tolist()
    probabilities = softmax(logits)
    ranked = sorted(range(3), key=probabilities.__getitem__, reverse=True)
    ids = encoded["input_ids"][0].tolist()
    tokens = tokenizer.convert_ids_to_tokens(ids)
    types = encoded.get("token_type_ids", torch.zeros_like(encoded["input_ids"]))[0].tolist()
    return {
        "premise": premise,
        "hypothesis": hypothesis,
        "sequence_length": len(ids),
        "input_ids": ids,
        "tokens": tokens,
        "token_type_ids": types,
        "logits_by_class": {LABELS[i]: round(logits[i], 6) for i in range(3)},
        "probabilities": {LABELS[i]: round(probabilities[i], 6) for i in range(3)},
        "predicted": LABELS[ranked[0]],
        "top2_margin": round(probabilities[ranked[0]] - probabilities[ranked[1]], 6),
        "decisive_margin_entailment_minus_contradiction": round(probabilities[0] - probabilities[2], 6),
    }


def mean_pool(output, mask):
    hidden = output.last_hidden_state
    expanded = mask.unsqueeze(-1).expand(hidden.size()).float()
    return (hidden * expanded).sum(1) / expanded.sum(1).clamp(min=1e-9)


def rank_chunks(claim: str, chunks: list[str]) -> dict:
    try:
        tokenizer = AutoTokenizer.from_pretrained(EMBEDDING_ID, local_files_only=True)
        model = AutoModel.from_pretrained(EMBEDDING_ID, local_files_only=True).eval()
    except Exception as error:
        return {"status": "UNAVAILABLE", "reason": str(error)}
    texts = [claim, *chunks]
    encoded = tokenizer(texts, padding=True, truncation=True, max_length=512, return_tensors="pt")
    with torch.inference_mode():
        vectors = torch.nn.functional.normalize(mean_pool(model(**encoded), encoded["attention_mask"]), p=2, dim=1)
    scores = torch.matmul(vectors[1:], vectors[0]).tolist()
    ranked = sorted(zip(chunks, scores), key=lambda item: item[1], reverse=True)
    return {
        "status": "OK",
        "threshold": 0.25,
        "top_k": 3,
        "ranked": [
            {"chunk": chunk, "similarity": round(score, 6), "selected": rank < 3 and score >= 0.25}
            for rank, (chunk, score) in enumerate(ranked)
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    tokenizer = AutoTokenizer.from_pretrained(CHECKPOINT, local_files_only=True)
    model = AutoModelForSequenceClassification.from_pretrained(CHECKPOINT, local_files_only=True).eval()

    cases = []
    for case in [*CANCER_CASES, SHORT_CASE]:
        cases.append({**case, "traces": [trace_pair(tokenizer, model, case["premise"], claim) for claim in case["claims"]]})
    extension = [{**case, "trace": trace_pair(tokenizer, model, case["premise"], case["hypothesis"])} for case in ADVERSARIAL_EXTENSION]
    chunk_ranking = rank_chunks("Brasileiro encontrou cura do câncer.", ARTICLE_CHUNKS)
    if chunk_ranking.get("status") == "OK":
        for row in chunk_ranking["ranked"]:
            if row["selected"]:
                row["nli_trace"] = trace_pair(
                    tokenizer, model, row["chunk"], "Brasileiro encontrou cura do câncer."
                )
    result = {
        "method": {
            "checkpoint": str(CHECKPOINT),
            "label_order": list(LABELS),
            "production_thresholds_unchanged": {"similarity": 0.25, "nli_confidence": 0.50},
            "notes": "Diagnostic only; no threshold, aggregation, DT-25, DT-26, or DT-29 change.",
        },
        "cases": cases,
        "chunk_selection_probe": {
            "claim": "Brasileiro encontrou cura do câncer.",
            "chunks": ARTICLE_CHUNKS,
            "result": chunk_ranking,
        },
        "adversarial_extension": extension,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), "cases": len(cases), "extension": len(extension)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
