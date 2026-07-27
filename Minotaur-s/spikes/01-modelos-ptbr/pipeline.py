# -*- coding: utf-8 -*-
"""
Pipeline do SPIKE 1: embedding -> similaridade de cosseno -> NLI.

Reproduz, em Python, a mesma direção definida na spec para o app:
  RF-06: embedding da afirmação e do chunk + similaridade de cosseno.
  RF-07: NLI com premissa = chunk, hipótese = afirmação -> distribuição
         entre entailment / contradiction / neutral.

Este é código de VALIDAÇÃO descartável (spike), fora do projeto iOS.
Não calibra limiares [EM ABERTO]; apenas reporta os números observados.
"""

import numpy as np
import torch
from sentence_transformers import SentenceTransformer
from transformers import AutoModelForSequenceClassification, AutoTokenizer

EMBEDDING_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
NLI_MODEL = "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7"

_embedder = None
_nli_tokenizer = None
_nli_model = None


def _load():
    """Carrega os modelos uma única vez (lazy)."""
    global _embedder, _nli_tokenizer, _nli_model
    if _embedder is None:
        print(f"[carregando embeddings] {EMBEDDING_MODEL} ...", flush=True)
        _embedder = SentenceTransformer(EMBEDDING_MODEL)
    if _nli_model is None:
        print(f"[carregando NLI]        {NLI_MODEL} ...", flush=True)
        _nli_tokenizer = AutoTokenizer.from_pretrained(NLI_MODEL)
        _nli_model = AutoModelForSequenceClassification.from_pretrained(NLI_MODEL)
        _nli_model.eval()


def cosine_similarity(chunk: str, afirmacao: str) -> float:
    """Similaridade de cosseno entre chunk e afirmação (RF-06.5)."""
    _load()
    embs = _embedder.encode([chunk, afirmacao], normalize_embeddings=True)
    return float(np.dot(embs[0], embs[1]))


def nli(chunk: str, afirmacao: str) -> dict:
    """
    NLI com premissa = chunk, hipótese = afirmação (RF-07.1).
    Retorna a distribuição de probabilidade e o rótulo de maior probabilidade.
    A ordem dos rótulos vem de model.config.id2label (não é hardcoded).
    """
    _load()
    inputs = _nli_tokenizer(
        chunk, afirmacao, truncation=True, max_length=512, return_tensors="pt"
    )
    with torch.no_grad():
        logits = _nli_model(**inputs).logits[0]
    probs = torch.softmax(logits, dim=-1).tolist()

    # id2label do modelo -> {"entailment": p, "neutral": p, "contradiction": p}
    dist = {}
    for idx, label in _nli_model.config.id2label.items():
        dist[label.lower()] = probs[int(idx)]

    label = max(dist, key=dist.get)
    return {"label": label, "score": dist[label], "dist": dist}


def analyze_pair(chunk: str, afirmacao: str) -> dict:
    """Roda o pipeline completo para um par (chunk, afirmação)."""
    sim = cosine_similarity(chunk, afirmacao)
    r = nli(chunk, afirmacao)
    return {
        "similarity": sim,
        "label": r["label"],
        "score": r["score"],
        "dist": r["dist"],
    }
