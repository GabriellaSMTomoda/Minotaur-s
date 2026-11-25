#!/usr/bin/env python3
"""Exports the XLM-R unigram log-probabilities as a compact Float16 table for the app.

`EvidenceScorer` uses them to find the most specific ("anchor") words of a claim without
parsing the 17 MB tokenizer JSON on the device. Output: little-endian float16, one per id.
"""
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Minotaur-s/Resources/Tokenizers/EmbeddingsTokenizer.json"
TARGET = ROOT / "Minotaur-s/Resources/Verification/EmbeddingsPieceScores.bin"

vocab = json.loads(SOURCE.read_text())["model"]["vocab"]
data = b"".join(struct.pack("<e", max(-60.0, float(score))) for _, score in vocab)
TARGET.write_bytes(data)
print(f"{len(vocab)} scores -> {TARGET} ({len(data)} bytes)", file=sys.stderr)
