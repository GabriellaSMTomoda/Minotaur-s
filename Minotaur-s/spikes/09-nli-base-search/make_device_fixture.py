# -*- coding: utf-8 -*-
"""Gera entradas das sondas do gate a partir do tokenizador BERTimbau-base."""
from __future__ import annotations

import json
from pathlib import Path

from transformers import AutoTokenizer

HERE = Path(__file__).resolve().parent
BUILD = HERE / "build"
MANIFEST = BUILD / "conversion_manifest.json"


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    tokenizer = AutoTokenizer.from_pretrained(manifest["model_id"])
    result = {"model_id": manifest["model_id"], "variants": {}}

    for variant in manifest["variants"]:
        fixed = variant["shape"] if isinstance(variant["shape"], int) else None
        probes = []
        for recorded in variant["probes"]:
            kwargs = {
                "return_tensors": None,
                "truncation": "only_first",
                "max_length": fixed or 512,
            }
            if fixed is not None:
                kwargs["padding"] = "max_length"
            encoded = tokenizer(recorded["premise"], recorded["hypothesis"], **kwargs)
            probes.append(
                {
                    "kind": recorded["kind"],
                    "input_ids": encoded["input_ids"],
                    "attention_mask": encoded["attention_mask"],
                    "token_type_ids": encoded["token_type_ids"],
                    "expected_coreml_logits": recorded["coreml_logits"],
                }
            )
        result["variants"][variant["name"]] = probes

    destination = BUILD / "device_fixture.json"
    destination.write_text(json.dumps(result, ensure_ascii=False), encoding="utf-8")
    print(f"OK -> {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
