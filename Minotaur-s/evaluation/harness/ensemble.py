"""NLI ensemble on an existing harness run: BERTimbau (app) + MiniLMv2-L6 (Spike 10).

Scores the same premises again with the second model and writes one derived run per strategy,
so `run_dev.py report --run <run>-<strategy> --aggregator v3` compares them without network.

Usage: `.venv/bin/python ensemble.py v3b`
"""
import json
import sys
from pathlib import Path

import coremltools as ct
import numpy as np

import models
from run_dev import ARTIFACTS

L6 = Path(__file__).resolve().parents[2] / "spikes/10-ensemble-minilm/build/NLI2.mlmodelc"
L6_LABELS = ["entailment", "neutral", "contradiction"]  # spikes/10-ensemble-minilm/NLI2Labels.json


class MiniLMNLI:
    max_len = 512

    def __init__(self):
        self.model = ct.models.CompiledMLModel(str(L6), compute_units=ct.ComputeUnit.CPU_ONLY)
        self.tok = models._load_tokenizer("EmbeddingsTokenizer")  # identical vocabulary (Spike 10)
        self.bos, self.eos = self.tok.token_to_id("<s>"), self.tok.token_to_id("</s>")

    def predict(self, premise: str, hypothesis: str) -> dict:
        p = self.tok.encode(premise, add_special_tokens=False).ids
        h = self.tok.encode(hypothesis, add_special_tokens=False).ids[: self.max_len - 4]
        p = p[: max(0, self.max_len - 4 - len(h))]
        ids = [self.bos] + p + [self.eos, self.eos] + h + [self.eos]
        out = self.model.predict({"input_ids": np.array([ids], dtype=np.int32),
                                  "attention_mask": np.ones((1, len(ids)), dtype=np.int32)})
        logits = np.asarray(out["logits"], dtype=np.float64).reshape(-1)
        e = np.exp(logits - logits.max())
        return dict(zip(L6_LABELS, (e / e.sum()).tolist()))


def combine(a: dict, b: dict, strategy: str) -> dict:
    if strategy == "avg":
        out = {k: (a[k] + b[k]) / 2 for k in L6_LABELS}
    elif strategy == "w70":
        out = {k: 0.7 * a[k] + 0.3 * b[k] for k in L6_LABELS}
    elif strategy == "agree":  # a class only keeps the probability both models give it
        e, c = min(a["entailment"], b["entailment"]), min(a["contradiction"], b["contradiction"])
        out = {"entailment": e, "contradiction": c, "neutral": 1 - e - c}
    elif strategy == "veto_c":  # BERTimbau as is, but contradiction needs the second model's agreement
        c = min(a["contradiction"], b["contradiction"])
        out = {"entailment": a["entailment"], "contradiction": c, "neutral": 1 - a["entailment"] - c}
    else:
        raise ValueError(strategy)
    return {k: round(v, 4) for k, v in out.items()}


STRATEGIES = ("avg", "w70", "agree", "veto_c")

if __name__ == "__main__":
    run = sys.argv[1]
    l6 = MiniLMNLI()
    outs = {s: ARTIFACTS / f"{run}-{s}" for s in STRATEGIES}
    for d in outs.values():
        d.mkdir(exist_ok=True)
    for path in sorted((ARTIFACTS / run).glob("*.json")):
        res = json.loads(path.read_text())
        second = {}
        for src in res["sources"]:
            for ps in src["passages"]:
                second[ps["text"]] = second.get(ps["text"]) or l6.predict(ps["text"], res["claim"])
        for strategy, d in outs.items():
            derived = json.loads(json.dumps(res))
            for src in derived["sources"]:
                for ps in src["passages"]:
                    ps["probs_bert"] = ps["probs"]
                    ps["probs_l6"] = {k: round(v, 4) for k, v in second[ps["text"]].items()}
                    ps["probs"] = combine(ps["probs"], second[ps["text"]], strategy)
            (d / path.name).write_text(json.dumps(derived, ensure_ascii=False, indent=1))
    print("runs:", ", ".join(p.name for p in outs.values()))
