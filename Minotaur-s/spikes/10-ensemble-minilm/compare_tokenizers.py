# -*- coding: utf-8 -*-
"""Compara o tokenizer do MiniLMv2-L6 com o EmbeddingsTokenizer.json do app.

Checa: vocabulário (token, score, ordem), normalizer/pre_tokenizer/post_processor/
decoder, tokens adicionados, e ids em ~60 frases PT (texto isolado, sem e com
tokens especiais) + codificação de par premissa/hipótese.

Uso:  uv run python compare_tokenizers.py   -> build/tokenizer_compare.json
"""
import json
import os

from tokenizers import Tokenizer
from transformers import AutoTokenizer

from pt_data import ROOT, all_pairs, sentences

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL_ID = "MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli"
APP_TOK = os.path.join(ROOT, "Minotaur-s", "Resources", "Tokenizers", "EmbeddingsTokenizer.json")
APP_CFG = os.path.join(ROOT, "Minotaur-s", "Resources", "Tokenizers", "EmbeddingsTokenizerConfig.json")


def main():
    hf = AutoTokenizer.from_pretrained(MODEL_ID)
    nli_json_path = os.path.join(os.path.dirname(hf.vocab_file), "tokenizer.json")
    nli_cfg_path = os.path.join(os.path.dirname(hf.vocab_file), "tokenizer_config.json")
    with open(nli_json_path, encoding="utf-8") as f:
        nli = json.load(f)
    with open(APP_TOK, encoding="utf-8") as f:
        app = json.load(f)
    with open(nli_cfg_path, encoding="utf-8") as f:
        nli_cfg = json.load(f)
    with open(APP_CFG, encoding="utf-8") as f:
        app_cfg = json.load(f)

    rep = {"model": MODEL_ID}
    nv, av = nli["model"]["vocab"], app["model"]["vocab"]
    rep["vocab_size"] = {"nli2": len(nv), "embeddings": len(av)}
    rep["vocab_identical_tokens_and_order"] = [t for t, _ in nv] == [t for t, _ in av]
    rep["vocab_identical_with_scores"] = nv == av
    rep["vocab_first_token_diff"] = next(
        (i for i, (a, b) in enumerate(zip(nv, av)) if a != b), None)
    for key in ("normalizer", "pre_tokenizer", "post_processor", "decoder", "truncation", "padding"):
        rep[f"{key}_identical"] = nli.get(key) == app.get(key)
    rep["model_type"] = {"nli2": nli["model"]["type"], "embeddings": app["model"]["type"]}
    rep["model_other_fields_identical"] = (
        {k: v for k, v in nli["model"].items() if k != "vocab"}
        == {k: v for k, v in app["model"].items() if k != "vocab"})
    strip = lambda toks: [{k: v for k, v in t.items()} for t in toks]  # noqa: E731
    rep["added_tokens_identical"] = strip(nli["added_tokens"]) == strip(app["added_tokens"])
    rep["added_tokens"] = {"nli2": nli["added_tokens"], "embeddings": app["added_tokens"]}
    cfg_keys = sorted(set(nli_cfg) | set(app_cfg))
    rep["tokenizer_config_diffs"] = {
        k: {"nli2": nli_cfg.get(k), "embeddings": app_cfg.get(k)}
        for k in cfg_keys if nli_cfg.get(k) != app_cfg.get(k) and k != "added_tokens_decoder"}
    rep["truncation_padding_raw"] = {
        "nli2": {"truncation": nli.get("truncation"), "padding": nli.get("padding")},
        "embeddings": {"truncation": app.get("truncation"), "padding": app.get("padding")}}

    t_nli = Tokenizer.from_file(nli_json_path)
    t_app = Tokenizer.from_file(APP_TOK)
    for t in (t_nli, t_app):
        t.no_truncation()
        t.no_padding()
    sents = sentences(60)
    mism = []
    for s in sents:
        for special in (False, True):
            a = t_nli.encode(s, add_special_tokens=special).ids
            b = t_app.encode(s, add_special_tokens=special).ids
            h = hf(s, add_special_tokens=special)["input_ids"]
            if not (a == b == h):
                mism.append({"text": s, "special": special, "nli2": a, "app": b, "hf_slow_fast": h})
    rep["sentences_checked"] = len(sents)
    rep["sentence_encodings_checked"] = len(sents) * 2
    rep["sentence_mismatches"] = mism
    rep["total_tokens_checked"] = sum(len(t_app.encode(s, add_special_tokens=False).ids) for s in sents)

    # Par: o formato que o NLI precisa (<s> P </s></s> H </s>) vs. o que o
    # XLMRTokenizer.swift faz hoje (só texto isolado: <s> X </s>).
    pair_mism, pair_example = [], None
    for p in all_pairs():
        a = t_nli.encode(p["premise"], p["hypothesis"]).ids
        b = t_app.encode(p["premise"], p["hypothesis"]).ids
        body_p = t_app.encode(p["premise"], add_special_tokens=False).ids
        body_h = t_app.encode(p["hypothesis"], add_special_tokens=False).ids
        manual = [0] + body_p + [2, 2] + body_h + [2]
        h = hf(p["premise"], p["hypothesis"])["input_ids"]
        if pair_example is None:
            pair_example = {"hf_pair_head": h[:6], "hf_pair_sep_region": None}
            k = len(body_p) + 1
            pair_example["hf_pair_sep_region"] = h[k - 1:k + 3]
        if not (a == b == manual == h):
            pair_mism.append(p["id"])
    rep["pairs_checked"] = len(all_pairs())
    rep["pair_mismatches_vs_manual_<s>P</s></s>H</s>"] = pair_mism
    rep["pair_example"] = pair_example

    out = os.path.join(HERE, "build", "tokenizer_compare.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump({k: v for k, v in rep.items() if k != "added_tokens"} | {"added_tokens": rep["added_tokens"]},
                  f, ensure_ascii=False, indent=2)
    for k, v in rep.items():
        if k not in ("added_tokens", "sentence_mismatches"):
            print(f"{k}: {v}")
    print(f"sentence_mismatches: {len(mism)}")


if __name__ == "__main__":
    main()
