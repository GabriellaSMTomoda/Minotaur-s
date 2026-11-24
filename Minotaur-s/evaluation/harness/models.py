"""Loads the exact compiled Core ML models and tokenizers shipped in the app.

Mirrors `BERTTokenizer.swift`, `XLMRTokenizer.swift`, `NLIService.swift` and
`EmbeddingService.swift`. macOS only (Core ML).
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import numpy as np
import coremltools as ct
from tokenizers import Tokenizer

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "Minotaur-s" / "Resources"
MODELS = RESOURCES / "Models"
TOKENIZERS = RESOURCES / "Tokenizers"
LABELS = ("entailment", "neutral", "contradiction")


def _load_tokenizer(name: str) -> Tokenizer:
    tok = Tokenizer.from_file(str(TOKENIZERS / f"{name}.json"))
    tok.no_truncation()
    tok.no_padding()
    return tok


@dataclass(frozen=True)
class Probabilities:
    entailment: float
    neutral: float
    contradiction: float

    @property
    def best(self) -> str:
        if self.neutral >= self.entailment and self.neutral >= self.contradiction:
            return "neutral"
        return "entailment" if self.entailment >= self.contradiction else "contradiction"

    def of(self, label: str) -> float:
        return getattr(self, label)

    def as_dict(self) -> dict:
        return {"entailment": round(self.entailment, 4), "neutral": round(self.neutral, 4),
                "contradiction": round(self.contradiction, 4)}


def softmax(logits, temperature: float = 1.0) -> list[float]:
    values = [v / temperature for v in logits]
    m = max(values)
    exps = [math.exp(v - m) for v in values]
    total = sum(exps)
    return [e / total for e in exps]


class NLIModel:
    """BERTimbau-base PLUE (Spike 9). Premise = article text, hypothesis = claim."""

    max_len = 512

    def __init__(self, model_dir: Path = MODELS / "NLI.mlmodelc", tokenizer: str = "NLITokenizer",
                 labels_file: Path = TOKENIZERS / "NLILabels.json"):
        self.model = ct.models.CompiledMLModel(str(model_dir), compute_units=ct.ComputeUnit.CPU_ONLY)
        self.tok = _load_tokenizer(tokenizer)
        self.cls = self.tok.token_to_id("[CLS]")
        self.sep = self.tok.token_to_id("[SEP]")
        id2label = json.loads(labels_file.read_text())["id2label"]
        self.labels = [id2label[str(i)] for i in range(3)]
        self._cache: dict[tuple[str, str], tuple[list[float], Probabilities]] = {}

    def token_count(self, text: str) -> int:
        return len(self.tok.encode(text, add_special_tokens=False).ids)

    def encode_pair(self, premise: str, hypothesis: str):
        p = self.tok.encode(premise, add_special_tokens=False).ids
        h = self.tok.encode(hypothesis, add_special_tokens=False).ids
        body = self.max_len - 3
        h = h[:body]
        p = p[:max(0, body - len(h))]
        ids = [self.cls] + p + [self.sep] + h + [self.sep]
        types = [0] * (len(p) + 2) + [1] * (len(h) + 1)
        return ids, types

    def predict(self, premise: str, hypothesis: str, temperature: float = 1.0):
        key = (premise, hypothesis)
        if key in self._cache:
            return self._cache[key]
        ids, types = self.encode_pair(premise, hypothesis)
        n = len(ids)
        out = self.model.predict({
            "input_ids": np.array([ids], dtype=np.int32),
            "attention_mask": np.ones((1, n), dtype=np.int32),
            "token_type_ids": np.array([types], dtype=np.int32),
        })
        logits = [float(x) for x in np.asarray(out["logits"]).reshape(-1)]
        probs = softmax(logits, temperature)
        values = dict(zip(self.labels, probs))
        result = (logits, Probabilities(values["entailment"], values["neutral"], values["contradiction"]))
        self._cache[key] = result
        return result


class EmbeddingModel:
    """paraphrase-multilingual-MiniLM-L12-v2 (XLM-R tokenizer)."""

    max_len = 512

    def __init__(self, model_dir: Path = MODELS / "Embeddings.mlmodelc"):
        self.model = ct.models.CompiledMLModel(str(model_dir), compute_units=ct.ComputeUnit.CPU_ONLY)
        self.tok = _load_tokenizer("EmbeddingsTokenizer")
        self.bos = self.tok.token_to_id("<s>")
        self.eos = self.tok.token_to_id("</s>")
        self._cache: dict[str, np.ndarray] = {}

    def token_count(self, text: str) -> int:
        return len(self.tok.encode(text, add_special_tokens=False).ids)

    def embed(self, text: str) -> np.ndarray:
        if text in self._cache:
            return self._cache[text]
        body = self.tok.encode(text, add_special_tokens=False).ids[: self.max_len - 2]
        ids = [self.bos] + body + [self.eos]
        out = self.model.predict({
            "input_ids": np.array([ids], dtype=np.int32),
            "attention_mask": np.ones((1, len(ids)), dtype=np.int32),
        })
        vec = np.asarray(out["embedding"], dtype=np.float32).reshape(-1)
        self._cache[text] = vec
        return vec

    @staticmethod
    def cosine(a: np.ndarray, b: np.ndarray) -> float:
        na, nb = float(np.linalg.norm(a)), float(np.linalg.norm(b))
        return float(np.dot(a, b) / (na * nb)) if na > 0 and nb > 0 else 0.0


@lru_cache(maxsize=1)
def nli() -> NLIModel:
    return NLIModel()


@lru_cache(maxsize=1)
def embeddings() -> EmbeddingModel:
    return EmbeddingModel()
