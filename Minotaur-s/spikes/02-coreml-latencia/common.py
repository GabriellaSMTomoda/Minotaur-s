# -*- coding: utf-8 -*-
"""Utilidades compartilhadas do Spike 2 (conversão Core ML)."""
import os


def dir_size_mb(path: str) -> float:
    """Tamanho total de um .mlpackage (é um diretório) em MB."""
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            fp = os.path.join(root, f)
            if os.path.exists(fp):
                total += os.path.getsize(fp)
    return total / (1024 * 1024)


EMBEDDING_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
NLI_MODEL = "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7"
MAX_SEQ = 512  # limite do NLI (spec RF-06.2)
