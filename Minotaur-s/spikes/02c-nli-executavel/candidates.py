# -*- coding: utf-8 -*-
"""
SPIKE 2c — Candidatos a modelo de NLI que EXECUTAM em Core ML de device real.

Diferença central para o Spike 2b: aqui a ordem dos filtros é invertida. Um
candidato só avança se:
  1. converte para Core ML sem custom op,
  2. EXECUTA .predict() de fato em device (simulador iOS 18.6 + iPhone físico),
  3. tem qualidade PT-BR (dataset do Spike 1),
  4. cabe em NF-05 (<500 MB com os 113 MB dos embeddings).

Este módulo só declara os candidatos e o par PT-BR fixo usado para gerar a
referência de logits (a mesma tokenização é embarcada no harness para checar,
no device, se os logits batem — "converte sem erro" != "executa correto").

Código descartável, isolado do app.
"""

MAX_SEQ = 512  # limite do NLI (spec RF-06.2)

# `short`  -> nome curto usado nos arquivos <short>_int8.mlpackage e no manifest.
# `kind`   -> arquitetura base + POR QUE deveria (ou não) ser amigável ao Core ML,
#             documentado ANTES de testar (exigência do pedido).
# `expected_classes` -> 2 classes reprova automaticamente (RF-07.2).
CANDIDATES = [
    {
        "short": "L6",
        "id": "MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli",
        "kind": "MiniLMv2 destilado do XLM-R-large (6 camadas, h384). Atenção "
                "escalar padrão (softmax normal), sem custom autograd op — ao "
                "contrário do DeBERTa (XSoftmax/gather de posição relativa). "
                "Deveria converter E executar limpo. Já converteu no Spike 2b, "
                "mas nunca foi executado com .predict() em device.",
        "expected_classes": 3,
    },
    {
        "short": "L12",
        "id": "MoritzLaurer/multilingual-MiniLMv2-L12-mnli-xnli",
        "kind": "MiniLMv2 destilado do XLM-R-large (12 camadas). Mesma atenção "
                "padrão do L6, mais capacidade. Melhor PT-BR do Caminho 2 no "
                "Spike 2b (17/20). Converteu no 2b; nunca executado em device.",
        "expected_classes": 3,
    },
    {
        "short": "symanto",
        "id": "symanto/xlm-roberta-base-snli-mnli-anli-xnli",
        "kind": "XLM-R-base completo (12 camadas, RoBERTa). Atenção padrão. "
                "Vocab de 250k domina o tamanho. Converteu no 2b; nunca "
                "executado em device.",
        "expected_classes": 3,
    },
    {
        "short": "erniem",
        "id": "MoritzLaurer/ernie-m-base-mnli-xnli",
        "kind": "ERNIE-M base (Baidu, construído sobre RoBERTa/XLM-R, vocab 250k). "
                "Família DISTINTA das anteriores (não é XLM-R direto nem "
                "destilado da Microsoft), mas usa atenção multi-head padrão — a "
                "inovação do ERNIE-M (CAMLM/BTMLM) é só de pré-treino, o forward "
                "de inferência é transformer padrão. Incluído como seguro contra "
                "a hipótese 'toda a família XLM-R falha igual no device'. "
                "Candidato NOVO nesta rodada.",
        "expected_classes": 3,
    },
]

# Referências documentadas mas NÃO testadas (com o motivo):
#  - joeddav/xlm-roberta-large-xnli: XLM-R-large, softmax padrão, 3 classes, alta
#    qualidade, mas ~560 MB INT8 sozinho -> estoura NF-05 junto com embeddings.
#  - MoritzLaurer/xlm-v-base-mnli-xnli: softmax padrão, 3 classes, MAS vocab de
#    ~901k tokens -> matriz de embedding gigante, tamanho inviável para NF-05.
#  - MoritzLaurer/mDeBERTa-v3-base-xnli (patchado): já REPROVADO no Filtro 2 no
#    Spike 2 (crash MPSGraph em .all, BNNS em .cpuOnly, trava no simulador).
#  - ricardo-filho/bert-base-portuguese-cased-nli-assin-2: 2 classes -> RF-07.2.

# --- Par PT-BR fixo p/ gerar a referência de logits (NÃO é validação de acurácia).
# Trecho do dataset do Spike 1 (Agência Brasil, tarifa dos EUA), par de entailment
# claro. O MESMO par (já tokenizado por modelo) vai embarcado no harness para
# confirmar, no device, que os logits batem com o PyTorch.
NLI_PREMISE = (
    "A nova tarifa substitui a taxa global temporária de 10% aplicada desde "
    "fevereiro e se soma à sobretaxa de 25% sobre produtos brasileiros, em vigor "
    "desde o último dia 22. Com isso, parte das exportações do Brasil para o "
    "mercado estadunidense poderá enfrentar tributação de até 37,5%."
)
NLI_HYPOTHESIS = "As exportações brasileiras podem ser taxadas em até 37,5%."
