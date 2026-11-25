---
name: avaliar-verificador
description: Mede o acerto do Verificador no conjunto dev (não-gold) com o harness offline, compara com a última execução e aponta os erros. Usar depois de mudar regras de evidência, premissas, consultas, fontes ou modelo NLI, e antes de portar uma regra para o Swift.
---

# Avaliar o Verificador

O harness em `evaluation/harness/` reproduz o pipeline do app em Python usando **os mesmos `.mlmodelc`** (NLI BERTimbau e embeddings XLM-R) e as respostas de busca/HTML já cacheadas. Reavaliar não gasta créditos Tavily.

`evidence.py` é a implementação de referência das regras v3; `Services/Verificador/EvidenceScorer.swift` e `VerdictAggregator.swift` a espelham. Mudou um, mude o outro na mesma tarefa.

## Passos

1. Ambiente (uma vez): `cd evaluation/harness && uv sync`.
2. Escolha um nome novo de execução (ex.: `v3c`) para não sobrescrever a anterior.
3. Se mudou premissas, alinhamento temporal ou modelo, reanalise (roda NLI, ~5–10 min):
   ```sh
   HARNESS_OFFLINE=1 .venv/bin/python run_dev.py analyze --mode sentence --run v3c [--with-wiki]
   ```
   Se mudou só pontuação/agregação, pule este passo e reaproveite a execução anterior no `report`.
4. Relatório:
   ```sh
   HARNESS_OFFLINE=1 .venv/bin/python run_dev.py report --run v3c --aggregator v3
   ```
   Gera `evaluation/artifacts/harness/report-v3c-v3.md` (ignorado pelo Git) e imprime o resumo JSON.
5. Compare com a execução anterior: acerto e IC de Wilson, taxa de DIVERGENTE, **direção oposta** (CONFIRMADO↔CONTRADITO, o erro mais grave) e acerto por grupo (`trivial_true`, `trivial_false`, `quiz_hoax`, `quiz_news`).
6. Para entender um caso: `.venv/bin/python debug_case.py v3c dev-false-07` mostra cada passagem com E/N/C, similaridade, nomes, âncoras e o motivo de cada voto.
7. Para classificar todos os erros, delegue ao agente `analista-erros-verificador`.

## Regras

- O conjunto `evaluation/data/dev_claims.jsonl` é **dev, não-gold** (`review_status: pending_user_review`). Nunca o chame de teste cego, gold ou métrica de promoção; não invente revisores.
- Não aceite uma regra que suba o acerto às custas de mais erros de direção oposta.
- Rede só com `collect`/`collect-wiki`, que consomem a faixa de avaliação do Worker (200/mês) ou a API gratuita da Wikipédia. Confira `GET /_admin/usage` antes de coletas grandes. A chave de avaliação fica em `~/Library/Application Support/Minotaur-s/credentials/evaluation-key` e nunca entra no Git, em logs ou em relatórios.
- Depois de portar para o Swift, rode os testes `Minotaur-sTests/Verificador` no simulador.
