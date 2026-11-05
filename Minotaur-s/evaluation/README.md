# Avaliação e ajuste local do verificador

Esta pasta não contém dados dos usuários. `data/pending_candidates.jsonl` contém 204 candidatos públicos aproveitados do quiz, **zero afirmações aprovadas como gold**. Títulos, rótulos e justificativas do quiz podem estar errados. O importador não transfere as justificativas nem promove os rótulos a resultados esperados.

O alvo de 1.200 afirmações (600 treino, 300 calibração, 300 teste cego) depende de curadoria humana. Não preencher a diferença com paráfrases automáticas nem declarar 90%/70% sem executar a avaliação. `data/known_regressions.jsonl` preserva os 15 pares anteriores; eles nunca são teste cego.

## Curadoria

Para cada candidato, conferir a afirmação atômica, data de referência ISO 8601, entidades, números, unidade, atribuição e modalidade. Corrigir `event_id`/`family_id` para agrupar o mesmo evento e suas variantes, inclusive quando os URLs forem diferentes. Remover material que dependa de imagem, áudio ou contexto irrecuperável.

Dois revisores independentes identificados devem concordar sobre `verdict` e os trechos; divergências exigem adjudicação registrada antes de marcar `review_status=reviewed`. O campo `reviewers` registra identidades reais da revisão, nunca o nome de um script. Para resultados direcionais e divergentes, preencher `evidence` (`id`, `url`, `text`) e `sufficient_evidence_sets` (conjuntos completos de IDs suficientes para concluir). Rotular cada par NLI em `pairs` separadamente: uma matéria que contradiz uma notícia pode conter uma citação que, isoladamente, não a contradiz.

Rótulos: `CONFIRMADO`, `CONTRADITO`, `DIVERGENTE`, `SEM_INFORMACAO`, `NAO_ENCONTRADO`. Este último descreve a busca/corpus congelado daquela avaliação, não ausência universal de evidência. Arquivar os candidatos de busca, HTML público, data de acesso e falhas em `snapshots/` (ignorado pelo Git). Metadados de publicação não substituem a data do evento.

```sh
python3 dataset.py validate data/pending_candidates.jsonl
python3 dataset.py validate snapshots/reviewed.jsonl --require-reviewed
python3 dataset.py split snapshots/reviewed.jsonl snapshots/partitioned.jsonl
python3 -m unittest discover -s . -p 'test_*.py'
```

O particionamento rejeita menos de 1.200 casos, revisões ausentes, IDs duplicados e vazamento por evento, família ou fonte. Não divide grupos para atingir cotas. Manter o teste cego em arquivo separado, inacessível ao treino; revisar a distribuição temática/temporal antes de congelar e registrar SHA-256. O empacotamento determinístico não substitui a revisão da representatividade.

## Treino e calibração

Usar Python 3.11 e `requirements-ml.txt` num ambiente local; macOS/MPS ou CPU, sem API de inferência ou GPU paga. Recuperar primeiro o checkpoint BERTimbau-base validado do Spike 9. O script recusa começar com um checkpoint ausente ou outra ordem de classes, e valida os dados antes de importar PyTorch.

```sh
python train_domain.py snapshots/train-and-calibration.jsonl --checkpoint /caminho/checkpoint-validado --output artifacts/domain --device auto
# Após interrupção: repetir o comando com --resume.
python predict_pairs.py snapshots/calibration.jsonl --checkpoint artifacts/domain/checkpoint-best --output artifacts/calibration-logits.jsonl
python calibrate.py artifacts/calibration-logits.jsonl artifacts/temperature.json
python predict_pairs.py data/known_regressions.jsonl --checkpoint artifacts/domain/checkpoint-best --output artifacts/regressions.jsonl --regression
```

`train_domain.py` seleciona pelo macro-F1 da calibração, registra digest/seed/hash dos pesos e salva estado retomável a cada 25 updates. O arquivo de treino não pode conter partições `test`/`regression`. `calibrate.py` exige 300 claims de calibração com revisão independente e minimiza NLL. Isso não corrige erros de atribuição ou generalização e não promove o modelo automaticamente.

Converter o candidato isoladamente com o conversor do Spike 9, usando `--checkpoint artifacts/domain/checkpoint-best --output-dir artifacts/coreml-candidate`. Não substituir os modelos validados antes dos gates físicos, paridade e regressões. O conversor conserva os três inputs BERT e incorpora `model_version` no Core ML.

Para escolher limiares, produzir observações da **partição de calibração** com `id`, `found_articles`, `sources` e, por fonte, `origin_group`, `provenance`, `is_partial`, `temporal_alignment`, `duplicate_of`, `passages`. Cada passagem contém `id`, `url`, `text`, `logits`. IDs/textos são associados aos trechos anotados depois da inferência, nunca fornecidos como rótulos ao modelo.

```sh
python select_policy.py snapshots/calibration.jsonl artifacts/pipeline-calibration.jsonl artifacts/temperature.json artifacts/EvidencePolicy.json --model-version bertimbau-domain-DIGEST
```

A política seleciona conjuntamente o piso e o critério de fonte única (igual ou mais alto), mantendo precisão direcional ≥90% e cobertura dos casos solucionáveis ≥70%. Se nenhum candidato atende ambos, o comando falha; melhorar o sistema, não reduzir silenciosamente a cobertura. A política baseline embarcada mantém 0,50/temperatura 1 e fica identificada como **não calibrada** até existirem dados.

## Replay, métricas e promoção

`EvaluationReplayTests` executa o pipeline com os modelos reais e candidatos/HTML congelados, sem rede. É opt-in: instalar os pesos, passar `MINOTAURS_EVALUATION_CORPUS` e `MINOTAURS_EVALUATION_OUTPUT` no ambiente do runner de testes. Cada caso acrescenta `articles` (`url`, `title`, `html`, `publishedDate`) e `evidence` ao schema anotado. O replay usa o relógio de referência do caso. Ele mede extração, recuperação de passagens e decisão; **não comprova o recall do buscador ao vivo**. Falhas de execução devem ser contabilizadas separadamente, não removidas da amostra.

```sh
python metrics.py snapshots/test.jsonl artifacts/predictions.jsonl --output artifacts/report.json
python release_gate.py artifacts/promotion-report.json
```

`metrics.py` exige todos os IDs e considera corretos os resultados direcionais apenas com trechos suficientes e URLs compatíveis. Reporta matriz, macro-F1, precisão por direção, cobertura total e solucionável, recuperação, erros confiantes, créditos/latência e intervalos de Wilson. Ausência de observações é `null`, nunca 100%.

O relatório de promoção agrega `candidate`, `baseline`, `blind_test_claims`, `blind_test_sha256`, `tokenizer_parity_passed`, `coreml_parity_passed`, `critical_regressions_passed`, `physical_devices`, `model_sha256`, `policy_version`. Cada aparelho registra nome, `peak_ram_mb`, `verification_p95_seconds`, `free_storage_mb` e `cold_and_repeated_runs`. Exigir iPhone 13 físico e aparelho mais recente, RAM <1 GB, p95 ≤15 s, melhora de acerto completo e regressão de cobertura ≤3 pontos percentuais. Medir também embeddings/NLI, inicialização a frio e uso consecutivo. Simulador não substitui esses gates.

Depois de aprovado, versionar como um conjunto: modelo/tokenizer/labels, política, manifesto de hashes e evidências. A política vai ao bundle como `EvidencePolicy.json`, acompanhada de `VerificationModelManifest.json` com `modelVersion` igual ao metadado do Core ML. O app rejeita pares incompatíveis. Manter o conjunto anterior para rollback de código/assets.

## Manutenção

Mensalmente: revisar pelo menos 50 novos casos públicos; conferir extração/domínios; comparar cobertura e erro por tema/período; renovar o teste cego quando seus exemplos forem usados para diagnóstico. Reservar até 200 créditos mensais para avaliação autenticada pelo header `X-Evaluation-Key` do proxy. Não usar a chave da Tavily no app, em fixtures ou nos logs. Não coletar verificações dos usuários para formar o corpus.
