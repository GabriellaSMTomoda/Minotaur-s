# -*- coding: utf-8 -*-
"""
Utilidades compartilhadas do SPIKE 2b (alternativas de NLI conversíveis p/ Core ML).

Código descartável, isolado do app. Reaproveita padrões do Spike 2
(02-coreml-latencia): dir_size_mb, o wrapper backbone->logits e o fluxo
trace -> ct.convert(FLOAT16, iOS16) -> linear_quantize_weights(INT8).
"""
import os

MAX_SEQ = 512  # limite do NLI (spec RF-06.2)


def dir_size_mb(path: str) -> float:
    """Tamanho total de um .mlpackage (é um diretório) em MB."""
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            fp = os.path.join(root, f)
            if os.path.exists(fp):
                total += os.path.getsize(fp)
    return total / (1024 * 1024)


# --- Candidatos do Caminho 2 -------------------------------------------------
# Critério: atenção padrão (softmax normal, sem custom autograd op tipo XSoftmax),
# 3 classes NLI quando possível, tamanho compatível com NF-05 (<500 MB; embeddings
# já ocupam ~113 MB INT8).
#
# 'kind' documenta a expectativa arquitetural (verificada de fato pela conversão,
# não assumida). 'note' registra a ressalva relevante para o RESULTADO.md.
CANDIDATES = [
    {
        "id": "MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli",
        "kind": "XLM-R-large destilado (6 camadas, h384) — softmax padrão",
        "expected_classes": 3,
        "note": "candidato principal: pequeno, multilíngue (MNLI+XNLI), mesma "
                "lógica de transferência PT-BR do Spike 1",
    },
    {
        "id": "MoritzLaurer/multilingual-MiniLMv2-L12-mnli-xnli",
        "kind": "XLM-R destilado (12 camadas) — softmax padrão",
        "expected_classes": 3,
        "note": "mais capacidade que o L6, ainda pequeno",
    },
    {
        "id": "symanto/xlm-roberta-base-snli-mnli-anli-xnli",
        "kind": "XLM-R-base — softmax padrão",
        "expected_classes": 3,
        "note": "XLM-R base completo (várias bases NLI); vocab 250k domina o tamanho",
    },
    {
        "id": "ricardo-filho/bert-base-portuguese-cased-nli-assin-2",
        "kind": "BERTimbau (BERT PT-BR) — softmax padrão",
        "expected_classes": 2,
        "note": "PT-BR NATIVO e o menor; MAS ASSIN2 RTE tem 2 classes "
                "(entailment/none) — SEM contradiction. Não atende RF-07.2/RF-08.1 "
                "sozinho. Incluído com essa ressalva explícita.",
    },
]

# Referência fora de orçamento (qualidade alta, mas ~560 MB INT8 estoura NF-05):
#   joeddav/xlm-roberta-large-xnli  (XLM-R-large, softmax padrão, 3 classes)
# Não convertido por padrão para não baixar ~2GB; citado no RESULTADO como limite superior.
OUT_OF_BUDGET_REFERENCE = "joeddav/xlm-roberta-large-xnli"


# --- Par PT-BR real para sanity-check da conversão (NÃO é validação de acurácia) ---
# Trecho copiado do dataset do Spike 1 (Agência Brasil, tarifa dos EUA). Serve só
# para confirmar que o .mlpackage produz a MESMA distribuição que o PyTorch original.
NLI_PREMISE = (
    "A nova tarifa substitui a taxa global temporária de 10% aplicada desde "
    "fevereiro e se soma à sobretaxa de 25% sobre produtos brasileiros, em vigor "
    "desde o último dia 22. Com isso, parte das exportações do Brasil para o "
    "mercado estadunidense poderá enfrentar tributação de até 37,5%."
)
NLI_HYPOTHESIS = "As exportações brasileiras podem ser taxadas em até 37,5%."
