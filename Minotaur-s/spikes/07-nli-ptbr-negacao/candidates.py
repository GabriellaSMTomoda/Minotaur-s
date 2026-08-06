# -*- coding: utf-8 -*-
"""
SPIKE 7 — Candidatos de NLI com base NATIVA de português (caminho (a)).

Motivo do spike: todo candidato avaliado desde o Spike 1 é multilíngue
(MiniLMv2/XLM-R/mDeBERTa/ERNIE-M). A família de modelos com base treinada em
português — BERTimbau e derivados — nunca foi testada. A evidência aponta para
lá: o par "A Terra é redonda." / "A Terra é plana." dá entailment 0,54 em PT-BR
e contradiction 0,95 em inglês NO MESMO MODELO (investigação pós-Fase 5). Isso
é limitação de português, não de NLI.

ORDEM DOS FILTROS — a mesma do Spike 2c, que existe por causa do mDeBERTa:
  FILTRO 0  três classes NLI de verdade (RF-07.2)   <- barato, mata cedo
  FILTRO 1  converte para Core ML INT8 sem custom op
  FILTRO 2  EXECUTA em device real com logits batendo em PyTorch
  FILTRO 3  só então: qualidade PT-BR nos pares reais
O mDeBERTa passou por "converte" e "logits batem no desktop" e mesmo assim não
executa em device nenhum. Qualidade medida antes de execução é qualidade jogada
fora.

Código descartável, isolado do app.
"""

MAX_SEQ = 512  # limite do NLI (RF-06.2)


# --------------------------------------------------------------------------
# FILTRO 0 aplicado ANTES de baixar peso: reprovados por leitura de config/card.
# --------------------------------------------------------------------------
# Registrados aqui, e não omitidos, porque a razão de reprovação é o achado mais
# importante do caminho (a): **o corpus de NLI em português mais usado não tem
# classe de contradição**.
#
# ASSIN2 (Avaliação de Similaridade Semântica e Inferência Textual, 2019) rotula
# pares como ENTAILMENT ou NONE — é RTE binário. Um modelo treinado nele não
# consegue, por construção, produzir `contradiction`: o veredito CONTRADITO da
# RF-08.3 ficaria inalcançável e toda notícia falsa desmentida pelas fontes cairia
# em SEM_INFORMACAO. Isso elimina de uma vez a maior parte da família PT-BR.
REJECTED_BEFORE_DOWNLOAD = [
    {
        "id": "ruanchaves/bert-base-portuguese-cased-assin2-entailment",
        "base": "BERTimbau-base",
        "reason": "FILTRO 0: config.json tem num_labels=2 (ASSIN2 é RTE binário, "
                  "ENTAILMENT/NONE). Sem classe de contradição -> RF-07.2 e o "
                  "veredito CONTRADITO da RF-08.3 ficam inalcançáveis.",
    },
    {
        "id": "ruanchaves/bert-large-portuguese-cased-assin2-entailment",
        "base": "BERTimbau-large",
        "reason": "FILTRO 0: idem, num_labels=2.",
    },
    {
        "id": "giotvr/bertimbau_large_assin2_fine_tuned",
        "base": "BERTimbau-large",
        "reason": "FILTRO 0: config tem 3 saídas, mas o model card define a função "
                  "de inferência como ENTAILMENT ou NONE (ASSIN2). A terceira "
                  "saída é herança do setup de ASSIN v1 (entailment/paraphrase/"
                  "none), não uma classe de contradição.",
    },
    {
        "id": "giotvr/xlm_roberta_base_assin2_fine_tuned",
        "base": "XLM-R-base",
        "reason": "FILTRO 0: idem — ASSIN2, sem contradição. E a base é "
                  "multilíngue, ou seja, nem atende ao objetivo do caminho (a).",
    },
    {
        "id": "sagui-nlp/debertinha-ptbr-xsmall-assin2-rte",
        "base": "DeBERTinha (DeBERTa-v3 PT-BR)",
        "reason": "FILTRO 0 duplo: (1) ASSIN2/RTE binário; (2) DeBERTa-v3 usa "
                  "atenção desemaranhada (XSoftmax + gather de posição relativa), "
                  "a MESMA operação não-padrão que fez o mDeBERTa converter e "
                  "não executar em device (Spike 2). Reprovado cedo por decisão "
                  "explícita: não repetir aquele ciclo.",
    },
    {
        "id": "ricardo-filho/bert-base-portuguese-cased-nli-assin-2",
        "base": "BERTimbau-base",
        "reason": "FILTRO 0: architectures=['BertModel'], sem cabeça de "
                  "classificação — é sentence-transformer treinado com objetivo "
                  "NLI, produz embedding, não distribuição entailment/neutral/"
                  "contradiction. Não serve para RF-07.2.",
    },
    {
        "id": "nicholasKluge/TeenyTinyLlama-460m-Assin2",
        "base": "TeenyTinyLlama-460m (decoder PT-BR)",
        "reason": "FILTRO 0: ASSIN2 binário. Além disso 460M parâmetros em "
                  "decoder — tamanho e latência fora de NF-02/NF-05 para um "
                  "classificador de par.",
    },
]


# --------------------------------------------------------------------------
# Candidatos que passam o FILTRO 0 e vão para conversão + device.
# --------------------------------------------------------------------------
# `label_order`: ordem dos índices de saída. NUNCA presumida — vem do model card
# e é CONFIRMADA empiricamente por `probe_labels.py` antes de qualquer medição de
# qualidade. Trocar entailment por contradiction inverteria o veredito sem erro
# visível em lugar nenhum (é o primeiro item que a investigação pós-Fase 5 teve
# de refutar).
CANDIDATES = [
    {
        "short": "inferbr",
        "id": "felipesfpaula/bertimbau-large-InferBr-NLI",
        "base": "neuralmind/bert-large-portuguese-cased (BERTimbau-large)",
        "data": "InferBR — dataset de NLI escrito em PT-BR (não traduzido), 3 classes",
        "kind": "BERT clássico, 24 camadas, h1024. Atenção multi-head padrão com "
                "softmax normal e posição ABSOLUTA aprendida — nenhuma custom op, "
                "nada parecido com o XSoftmax/posição relativa do DeBERTa. É o "
                "perfil que converteu E executou limpo no Spike 2c. Risco "
                "conhecido: 335M parâmetros, o maior candidato já testado.",
        "label_order": ["contradiction", "entailment", "neutral"],
        "label_source": "model card do autor: '0 – Contradiction, 1 – Entailment, "
                        "2 – Neutral'. config.json traz LABEL_0/1/2 genéricos.",
    },
    {
        "short": "plue_bertimbau",
        "id": "giotvr/bertimbau_large_plue_mnli_fine_tuned",
        "base": "neuralmind/bert-large-portuguese-cased (BERTimbau-large)",
        "data": "PLUE/MNLI — MNLI traduzido para PT, 3 classes",
        "kind": "Mesma arquitetura do inferbr (BERTimbau-large). Serve para "
                "separar o efeito da BASE em português do efeito do DADO em "
                "português: mesma base, corpus traduzido em vez de nativo.",
        "label_order": ["entailment", "neutral", "contradiction"],
        "label_source": "convenção do MNLI, herdada pelo PLUE. config.json traz "
                        "0/1/2 sem nome — CONFIRMAR com probe_labels.py.",
    },
    {
        "short": "plue_xlmr",
        "id": "giotvr/xlm_roberta_base_plue_mnli_fine_tuned",
        "base": "XLM-R-base (multilíngue)",
        "data": "PLUE/MNLI — MNLI traduzido para PT, 3 classes",
        "kind": "CONTROLE, não candidato de produto. Mesma base multilíngue da "
                "família que já falha (XLM-R), mas com fine-tune em português. "
                "Existe para responder a pergunta que o resto do spike não "
                "responde sozinho: o ganho (se houver) vem da base em português "
                "ou bastaria fine-tune em PT sobre base multilíngue?",
        "label_order": ["entailment", "neutral", "contradiction"],
        "label_source": "idem plue_bertimbau — CONFIRMAR com probe_labels.py.",
    },
]


# Modelo atual (DT-18), incluído em todas as medições como linha de base.
BASELINE = {
    "short": "L6",
    "id": "MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli",
    "base": "MiniLMv2 destilado do XLM-R-large (multilíngue)",
    "data": "MNLI + XNLI",
    "kind": "Em produção hoje. 2/10 nos pares adversariais reais.",
    "label_order": ["entailment", "neutral", "contradiction"],
    "label_source": "config.json do checkpoint (id2label explícito).",
}


# Par PT-BR fixo para gerar a referência de logits do FILTRO 2 (não é medida de
# acurácia — é o mesmo par tokenizado por modelo, embarcado no harness para
# confirmar que o device produz os MESMOS logits que o PyTorch).
NLI_PREMISE = (
    "A nova tarifa substitui a taxa global temporária de 10% aplicada desde "
    "fevereiro e se soma à sobretaxa de 25% sobre produtos brasileiros, em vigor "
    "desde o último dia 22. Com isso, parte das exportações do Brasil para o "
    "mercado estadunidense poderá enfrentar tributação de até 37,5%."
)
NLI_HYPOTHESIS = "As exportações brasileiras podem ser taxadas em até 37,5%."
