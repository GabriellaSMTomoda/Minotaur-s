# Spike 9 — Resultado

> Integração posterior ao PASS da Etapa 3: ver `INTEGRACAO_RESULTADO.md`. O resultado deste
> spike permanece imutável; a integração não reexecutou o conjunto adversarial A/B/C.

## Etapa 1 — busca de checkpoint NLI PT-BR base

Data: 2026-08-03

## Resultado

**Nenhum checkpoint público encontrado atende simultaneamente aos requisitos da Etapa 1:**

- base nativa de português;
- porte *base* (aproximadamente 110 milhões de parâmetros);
- arquitetura BERT/atenção padrão, sem DeBERTa/XSoftmax;
- cabeça de classificação NLI com três classes semanticamente distintas: `entailment`, `neutral` e `contradiction`.

Portanto, **não há candidato que permita pular o fine-tune**. Conforme a regra de progressão do Spike 9, a investigação para aqui e a Etapa 2 só deve começar após autorização explícita.

Nenhum modelo foi baixado, convertido ou medido em device nesta etapa. Nenhum arquivo do app, `spec.md` ou `CLAUDE.md` foi alterado.

## Método

A busca combinou:

1. listagem paginada da API do Hugging Face para `pt` + `text-classification`;
2. buscas globais por `nli`, `mnli`, `xnli`, `entailment`, `contradiction`, `rte`, `assin`, `inferbr`, `plue`, `bertimbau nli` e `portuguese nli`;
3. busca por descendentes declarados das bases PT-BR conhecidas:
   - `neuralmind/bert-base-portuguese-cased`;
   - `PORTULAN/albertina-100m-portuguese-ptbr-encoder`;
   - `PortBERT/PortBERT_base`;
   - `ricardoz/BERTugues-base-portuguese-cased`;
   - `pysentimiento/bertabaporu-base-uncased`;
   - `josu/roberta-pt-br`;
   - `rdenadai/BR_BERTo`;
4. auditoria dos `config.json` dos resultados com sinal de NLI, de três rótulos ou de linhagem PT-BR;
5. consultas suplementares pelos nomes das bases combinados com NLI/XNLI/MNLI.

O snapshot reproduzível contém:

| Métrica | Quantidade |
|---|---:|
| Modelos `pt` + `text-classification` | 496 |
| Modelos únicos na união das buscas | 5.161 |
| Configurações auditadas | 706 |
| Resultados retidos para triagem semântica | 133 |
| Falhas de leitura de configuração | 64 |

As 64 falhas não foram tratadas automaticamente como resultado negativo. A maioria foi causada por HTTP 429 do Hub ou por repositório privado/gated. Os nomes e metadados foram preservados no snapshot e os itens com qualquer sinal de NLI ou português foram revistos separadamente nas páginas dos modelos. Nenhum deles revelou uma base PT-BR nativa, padrão, de porte base, com as três classes exigidas.

Artefatos:

- `search_hub.py`: coleta e classificação reproduzíveis, sem baixar pesos;
- `hub_audit.json`: snapshot integral da coleta e das decisões automáticas.

## Candidatos próximos e motivo de reprovação

| Modelo | Base/saída | Reprovação precoce |
|---|---|---|
| [`ruanchaves/bert-base-portuguese-cased-assin-entailment`](https://huggingface.co/ruanchaves/bert-base-portuguese-cased-assin-entailment) | BERTimbau-base, 3 saídas | ASSIN v1: `no entailment`, `entailment`, `paraphrase`. Não existe classe de contradição; `no entailment` colapsa neutralidade e contradição. |
| [`ruanchaves/bert-base-portuguese-cased-assin2-entailment`](https://huggingface.co/ruanchaves/bert-base-portuguese-cased-assin2-entailment) | BERTimbau-base, 2 saídas | ASSIN2/RTE binário. `CONTRADITO` é inalcançável. |
| [`pmfsl/bertimbau-base-finetuned-rte`](https://huggingface.co/pmfsl/bertimbau-base-finetuned-rte) | BERTimbau-base, 2 saídas | RTE binário sobre ASSIN2 (`None`/`Entails`). |
| [`ruanchaves/bert-base-portuguese-cased-faquad-nli`](https://huggingface.co/ruanchaves/bert-base-portuguese-cased-faquad-nli) | BERTimbau-base, 2 saídas | Classifica adequação de resposta em QA, não NLI de três vias. |
| [`wilsonmarciliojr/bertimbau-embed-nli`](https://huggingface.co/wilsonmarciliojr/bertimbau-embed-nli) | BERTimbau-base, `BertModel` | Modelo de embeddings/similaridade, sem cabeça classificadora NLI de três classes. |
| [`ricardo-filho/bert-base-portuguese-cased-nli-assin-2`](https://huggingface.co/ricardo-filho/bert-base-portuguese-cased-nli-assin-2) | BERTimbau-base, `BertModel` | Sentence Transformer/embedding; não produz a distribuição NLI necessária. |
| [`carlospaes120/bertimbau-base-stance`](https://huggingface.co/carlospaes120/bertimbau-base-stance) | BERTimbau-base, 3 saídas | As classes são `acusador`, `defensor`, `neutro`: tarefa de *stance* sobre tweet, não relação premissa–hipótese. |
| [`giotvr/bertimbau_large_plue_mnli_fine_tuned`](https://huggingface.co/giotvr/bertimbau_large_plue_mnli_fine_tuned) | BERTimbau-large, 3 saídas | Semântica correta, mas arquitetura *large*: `hidden_size=1024`, 24 camadas e 16 cabeças. É o modelo já reprovado no gate de RAM/latência do Spike 8. |
| [`BalaRajesh1/mmbert-small-nli`](https://huggingface.co/BalaRajesh1/mmbert-small-nli) | mmBERT multilíngue, ~0,1B, 3 saídas | Não é uma base nativa de português; deriva de mmBERT multilíngue/ModernBERT, fora do caminho arquitetural padrão solicitado. |

Também apareceram modelos de três classes sobre BERTimbau-base para sentimento, decisões judiciais, simplificação textual e outras tarefas. Ter três logits não basta: sem as três relações NLI, não são candidatos.

## Arquiteturas rejeitadas antes de qualquer download

Os únicos modelos auditados cuja configuração declarava explicitamente o trio `entailment` / `neutral` / `contradiction`, além do BERTimbau-large já conhecido, eram variantes multilíngues de DeBERTa, como:

- [`MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7`](https://huggingface.co/MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7);
- [`sileod/mdeberta-v3-base-tasksource-nli`](https://huggingface.co/sileod/mdeberta-v3-base-tasksource-nli);
- [`sagui-nlp/debertinha-ptbr-xsmall-assin2-rte`](https://huggingface.co/sagui-nlp/debertinha-ptbr-xsmall-assin2-rte), que além de DeBERTa é ASSIN2/RTE binário.

Foram reprovados cedo por não serem bases nativas PT-BR em BERT padrão e, no caso DeBERTinha, também pela tarefa binária. Não houve tentativa de conversão, coerente com o beco sem saída de DeBERTa/XSoftmax registrado no projeto.

## Ordem índice → rótulo

Não foi feita uma sonda de logits porque nenhum checkpoint passou pelo filtro semântico e arquitetural para se tornar candidato. A busca **não confiou em `id2label` para aprovar modelos**: os rótulos de configuração serviram apenas para localizar itens, e as exclusões foram confirmadas pela tarefa/dataset descritos nos cards e pela arquitetura declarada.

Se um checkpoint tivesse passado, a aprovação final da Etapa 1 dependeria de sondas inequívocas para confirmar empiricamente a ordem índice → rótulo. Não houve essa situação.

## Espaço livre do device

Não aplicável nesta etapa: não houve medição em device. A confirmação e o registro de espaço livre permanecem obrigatórios antes das medições da Etapa 2.

## Decisão da etapa

**Etapa 1: resultado negativo.** Não existe, entre os checkpoints públicos localizados, um NLI de três classes sobre base PT-BR nativa de porte base e arquitetura padrão que possa substituir o fine-tune planejado.

Próximo passo proposto, ainda não executado: Etapa 2, gate de arquitetura com BERTimbau-base e cabeça aleatória de três classes, somente após OK explícito.

---

## Etapa 2 — gate de arquitetura

Data: 2026-08-03

### Veredito

**O gate de arquitetura PASSA, com margem ampla nas duas regras.**

- **NF-06 (< 1 GB):** maior pico residente observado em qualquer fase: **383,5 MB**. O pico transiente carregando o NLI com o modelo de embeddings já vivo foi **364,5 MB**; na carga obrigatória de 180 embeddings + 15 pares, o pior resultado foi **301,0 MB**. Mesmo usando conservadoramente o maior número de todo o ensaio, restam **640,5 MB de margem** até 1.024 MB.
- **NF-02 (< 1 s por par):** `RangeDim` a 512 tokens teve mediana de **69,4 ms**; o modelo fixo em 512 teve **45,1 ms**. O pior comprimento medido permanece mais de 14 vezes abaixo do teto.

**A Etapa 3 não foi iniciada.** Este resultado apenas libera tecnicamente o plano de fine-tune; treino continua condicionado a OK explícito e à apresentação prévia de dataset, hiperparâmetros, custo e tempo.

### O que foi convertido

`neuralmind/bert-base-portuguese-cased`, com encoder pré-treinado e somente uma cabeça `Linear(768 → 3)` inicializada aleatoriamente, com seed fixa. O carregador confirmou que os únicos pesos novos são `classifier.weight` e `classifier.bias`.

| Propriedade | Valor |
|---|---:|
| Parâmetros totais | 108.925.443 |
| Hidden size | 768 |
| Camadas / cabeças | 12 / 12 |
| Vocabulário | 29.794 |
| `.mlpackage` INT8 | 104,2–104,4 MB |
| App de medição (embeddings + NLI) | 219 MB |
| Compute units | `.cpuOnly` |

Foram gerados quatro modelos Core ML distintos; “fixo” não foi simulado repetindo uma entrada num modelo dinâmico:

- `RangeDim(1...512)`;
- shape fixo de 256 tokens;
- shape fixo de 384 tokens;
- shape fixo de 512 tokens.

Cada variante foi instalada separadamente para não somar modelos no device.

### Device e espaço em disco

Medição em **iPhone 16 físico (`iPhone17,3`), iOS 26.3.1 (a)**.

Antes do gate foram encontrados e removidos apenas dois apps descartáveis antigos de benchmark, `com.spike.ramgate8` e `com.spike.coremlbench`, que ainda continham modelos dos Spikes 7/8. Nenhum app ou dado do usuário foi removido; ambos são recuperáveis por rebuild dos spikes correspondentes.

| Variante | Livre após instalar, antes de carregar modelos | Mínimo durante a rodada |
|---|---:|---:|
| `RangeDim(1...512)` | 1.591 MB | 1.132 MB |
| Fixo 256 | 1.566 MB | 1.119 MB |
| Fixo 384 | 1.580 MB | 1.117 MB |
| Fixo 512 | 1.563 MB | 1.117 MB |

O mínimo ficou **491 MB acima** dos 626 MB associados à degradação do Spike 8. O runner impunha ainda um preflight conservador de 800 MB e teria abortado antes de carregar qualquer modelo.

### RAM — dois modelos vivos e carga obrigatória

As quatro variantes rodaram a mesma carga do Spike 8: 180 embeddings reais e os mesmos 15 pares de NLI, com os dois modelos vivos do carregamento até o fim.

| NLI | Shape dos 15 pares | Pico residente na fase NLI | Pico `phys_footprint` | Pico após repetir toda a verificação |
|---|---|---:|---:|---:|
| `RangeDim(1...512)` | reais: 135–241 | **294,3 MB** | 20,2 MB | 294,3 MB |
| Fixo 256 | todos com padding a 256 | **294,1 MB** | 19,9 MB | 294,2 MB |
| Fixo 384 | todos com padding a 384 | **297,0 MB** | 22,5 MB | 297,0 MB |
| Fixo 512 | todos com padding a 512 | **300,9 MB** | 26,3 MB | 301,0 MB |

As métricas divergiram porque grande parte das páginas do Core ML apareceu como memória residente, mas não como `phys_footprint`. Para não obter um passe artificial pelo número menor, o veredito usa **resident**, a métrica maior nesta rodada. Mesmo incluindo o maior transiente de todo o ensaio — 383,5 MB — o resultado fica muito distante de 1 GB.

A segunda verificação não cresceu em relação à primeira: não há sinal de memória em escada.

### Latência por comprimento

Cada mediana abaixo vem de 9 predições com o shape aquecido, em processo físico e com os dois modelos carregados. Os cenários de comprimento foram lançados em processos separados para não acumular especializações na mesma leitura de pico.

| Tokens | `RangeDim` | Shape fixo equivalente | Ganho do fixo |
|---:|---:|---:|---:|
| 77 | 14,2 ms | — | — |
| 128 | 18,9 ms | — | — |
| 256 | 31,6 ms | 20,7 ms | 34,5% |
| 384 | 48,1 ms | 31,7 ms | 34,1% |
| 512 | **69,4 ms** | **45,1 ms** | 35,0% |

As primeiras predições, que podem incluir preparação do shape, também ficaram abaixo de 1 s; o maior tempo frio da rodada final foi 230,6 ms.

Na carga real completa da fase NLI:

| Configuração | Mediana por par | 15 pares |
|---|---:|---:|
| `RangeDim`, comprimentos reais 135–241 | 21,9 ms | 380,7 ms |
| Fixo 256 | 21,6 ms | 333,0 ms |
| Fixo 384 | 31,5 ms | 477,9 ms |
| Fixo 512 | 45,6 ms | 866,9 ms |

Manter RF-06.2 em 512 e adotar shape fixo significa preencher **todo par** até 512. Isso elimina especializações e acelera o caso isolado de 512 tokens, mas torna a carga real 2,28 vezes mais lenta que `RangeDim`, pois os pares reais desta fixture são menores.

### Efeito de shape fixo versus `RangeDim`

O efeito de ~124 MB observado no BERT-large do Spike 8 **não se repetiu no BERT-base**:

- `RangeDim` com 15 comprimentos reais: 294,3 MB residentes;
- fixo 256, que contém todos esses pares sem truncamento nesta fixture: 294,1 MB;
- fixo 512: 301,0 MB, ligeiramente maior por executar sempre o shape máximo.

Portanto, shape fixo **não é necessário para passar a NF-06**. Seu benefício mensurável aqui é a otimização de latência para um comprimento conhecido; seu custo é padding, e em 512 esse custo domina a carga real.

### O que mudaria com orçamento menor que 512 na RF-06.2

Sem decidir a RF, os dados isolam o efeito arquitetural de dois tetos alternativos:

| Teto | Latência dinâmica no teto | Pico residente no par | Pico footprint no par | Diferença vs. 512 |
|---:|---:|---:|---:|---|
| 512 | 69,4 ms | 220,1 MB | 30,3 MB | referência |
| 384 | 48,1 ms | 213,4 MB | 24,4 MB | −30,7% latência; −6,7 MB resident |
| 256 | 31,6 ms | 208,5 MB | 20,2 MB | −54,5% latência; −11,6 MB resident |

Reduzir o orçamento ataca RAM e latência ao mesmo tempo, mas o ganho de RAM é pequeno porque o BERT-base já está longe do teto. O trade-off material passa a ser **qualidade/truncamento de evidência**, não viabilidade arquitetural. Na fixture atual, o maior par tem 241 tokens e cabe em 256; isso não prova que todos os pares de produção caberão. Nenhuma alteração foi feita na RF-06.2.

### Ordem índice → rótulo e paridade

Uma cabeça aleatória não possui ordem semântica empiricamente identificável. Declarar `id2label` não transforma índice em classe, e por isso o gate **não afirma** uma ordem `entailment`/`neutral`/`contradiction`.

Foram usadas três sondas inequívocas — entailment, contradição e neutralidade — nas quatro variantes. O resultado confirma justamente a ausência de semântica treinada: a cabeça aleatória escolhe índice 1 tanto para entailment quanto para contradição e índice 0 para neutralidade.

O que podia e precisava ser confirmado nesta etapa era a **preservação dos índices na conversão**:

- 12/12 sondas com `cos = 1,000000` entre Core ML no Mac e Core ML no iPhone;
- 12/12 com o mesmo `argmax`;
- os três logits coincidem até as seis casas registradas.

Após o fine-tune, a ordem semântica deverá obrigatoriamente ser estabelecida de novo com sondas inequívocas; o `id2label` do config não será aceito como evidência.

### Artefatos da Etapa 2

| Arquivo | Finalidade |
|---|---|
| `convert_architecture_gate.py` | Encoder BERTimbau-base + cabeça aleatória; conversão das quatro variantes |
| `make_device_fixture.py` | Entradas reproduzíveis das sondas de paridade |
| `run_architecture_gate.sh` | Build, preflight de disco, instalação separada e execução física |
| `xcode-bench/` | Harness iOS de RAM, latência e paridade |
| `device_results_iphone.log` | Saída crua do iPhone |
| `summarize_gate.py` | Parser das linhas estruturadas |
| `build/conversion_manifest.json` | Arquitetura, seed, hash da cabeça e referência dos logits |
| `build/gate_summary.json` | Consolidação numérica do gate |

### Decisão da etapa

**Etapa 2 aprovada:** a arquitetura BERTimbau-base de três classes cabe com margem no iPhone 16 e atende à latência mesmo em 512 tokens.

**PARE aqui. Não treinar sem novo OK.** O próximo passo, após autorização, é somente apresentar o plano da Etapa 3 antes de consumir GPU.

---

## Etapa 3 — fine-tune BERTimbau-base + PLUE/MNLI

**Status em 2026-08-05: PASS — Etapa 3 concluída, sem integração no app.** O
treino, a seleção exclusivamente por PLUE, as sondas empíricas, a avaliação
adversarial única, a conversão Core ML e o gate físico `.cpuOnly` terminaram.
Nenhum arquivo do app, `spec.md` ou `CLAUDE.md` foi alterado.

O custo financeiro externo real foi **R$ 0**. Nenhum provedor de GPU, API,
storage ou serviço pago foi utilizado.

### Corpus auditado antes do treino

- release: PLUE v1.0.0, `MNLI.zip`, 118.915.125 bytes;
- SHA-256 do ZIP: `20c9d4ef02743d2143e91ae52c68d4d9f3db90ab90b5835cb523b3878f5a5845`;
- `train.tsv`: 392.702 linhas, MD5
  `df6dbc8cb3e3c76f6985fd0d327f01aa`, exatamente o hash publicado no DVC;
- classes no treino: 130.899 entailment, 130.900 neutral e 130.903
  contradiction;
- 40 linhas oficiais têm hipótese vazia e são excluídas de forma explícita;
  restam **392.662 pares válidos**;
- `dev_matched.tsv`: 9.815 pares, sem texto vazio;
- ordem usada para produzir os alvos: 0 entailment, 1 neutral, 2
  contradiction. Essa ordem foi posteriormente confirmada de forma empírica;
  o config não foi aceito como prova.

O relatório completo da auditoria é gerado em
`build/plue/dataset_audit.json`. O conjunto A/B/C do Spike 7 não é importado
pelo programa de treino e não participa da seleção.

### Protocolo efetivamente executado

| Item | Valor |
|---|---|
| Base | `neuralmind/bert-base-portuguese-cased` |
| Cabeça | classificação de sequência, 3 logits |
| Épocas | 3 |
| Comprimento de treino | 256 tokens |
| Microbatch / acumulação | 16 / 2 |
| Batch efetivo | 32 |
| Otimizador | AdamW |
| LR / schedule | 2e-5, linear, warm-up 10% |
| Weight decay / clip | 0,01 / 1,0 |
| Seed | 42 |
| Precisão local | FP32 |
| Seleção | maior macro-F1 no `dev_matched`; menor loss desempata |

### Falha local preservada e correção operacional

A primeira tentativa usou microbatch 32 e acumulação 1. O smoke test curto
cabia, mas a execução longa falhou no update 4.700, ainda na primeira época e
antes de criar qualquer checkpoint, com:

`MPS backend out of memory (allocated: 16,05 GB; other allocations: 14,09 GB;
max allowed: 30,19 GB)`.

Os logs foram preservados como `build/training-attempt1-dynamic-b32.log` e
`build/training-attempt1-dynamic-b32.err.log`. A/B/C permaneceu selado. A falha
é compatível com acúmulo/fragmentação do backend ao processar milhares de
shapes dinâmicos; não é evidência sobre a RAM de inferência no iPhone.

A segunda tentativa mantém seed, dados, ordem, LR, schedule, três épocas e
**batch efetivo 32**, mas volta ao microbatch planejado 16 × acumulação 2. O
padding dinâmico é arredondado para múltiplos de 32, limitando o universo a oito
shapes, e o cache MPS não utilizado é liberado a cada 100 updates. RAM alocada e
RAM do driver passam a ser registradas no log a cada 100 updates. São mudanças
operacionais para viabilizar o mesmo protocolo sem custo externo, não ajuste de
qualidade após avaliação.

Agrupar batches por comprimento reduz padding e melhora throughput.
FP16 foi rejeitado no MPS porque o `GradScaler` do PyTorch 2.7 tenta criar um
tensor `float64`, operação não suportada pelo backend; não foi aceito treino sem
escala por risco de instabilidade numérica.

### Conclusão do treino e seleção PLUE

A segunda tentativa terminou com `status=COMPLETE`, consumiu exatamente as três
épocas e produziu 36.813 atualizações. O tempo computado pelo runner foi
23.333,10 s (**6 h 28 min 53 s**), a 50,49 exemplos/s em média. Entre a criação
do manifesto e o resumo final decorreram aproximadamente 7 h 15 min, incluindo
validações, serialização e períodos em que o host reduziu o throughput.

O validador independente `validate_training_result.py` usa somente artefatos
PLUE, recalcula a seleção e não importa o dataset do Spike 7. Resultado:
**PASS**, sem falhas. Confirmou 392.662 pares válidos de treino, 9.815 de
validação, seed 42, três épocas, batch efetivo 32, LR 2e-5, 36.813 updates e
1.177.986 exemplos vistos. `checkpoint-best` corresponde à época 3, escolhida
por maior macro-F1; o loss não precisou desempatar.

| Época | Update | Macro-F1 | Accuracy | Eval loss |
|---:|---:|---:|---:|---:|
| 1 | 12.271 | 0,806877 | 0,807438 | 0,499353 |
| 2 | 24.542 | 0,807673 | 0,808253 | 0,508679 |
| **3** | **36.813** | **0,816626** | **0,817015** | 0,542568 |

Matriz de confusão da época selecionada, linhas = classe real e colunas =
predição, na ordem entailment / neutral / contradiction:

```text
[[2804, 455, 220],
 [ 250,2503, 370],
 [ 180, 321,2712]]
```

| Classe | Precision | Recall | F1 | Suporte |
|---|---:|---:|---:|---:|
| entailment | 0,867038 | 0,805979 | 0,835394 | 3.479 |
| neutral | 0,763342 | 0,801473 | 0,781943 | 3.123 |
| contradiction | 0,821320 | 0,844071 | 0,832540 | 3.213 |

O checkpoint contém 436.616.281 bytes. Hash principal:

- `model.safetensors` SHA-256:
  `e686a09bded722ab45ae6f48a5826c4ecd4a3e2e254b2512b34891a30a7bb28d`.

Os hashes de todos os arquivos ficam em `build/training_validation.json`.

### Corpus e hashes

| Artefato | Tamanho/linhas | Hash |
|---|---:|---|
| `MNLI.zip` PLUE v1.0.0 | 118.915.125 bytes | SHA-256 `20c9d4ef02743d2143e91ae52c68d4d9f3db90ab90b5835cb523b3878f5a5845` |
| `train.tsv` | 392.702 linhas | MD5 `df6dbc8cb3e3c76f6985fd0d327f01aa`; SHA-256 `ff4de849d1537238ef2b56c77ee7fe1ca47c7962baf44c38bbae579b9efc70c1` |
| `dev_matched.tsv` | 9.815 linhas | MD5 `dfb55ab19b1e0bec5f048681d92b91ad`; SHA-256 `a5e15efbcebe833c7449933738e8741d16dbca4ddbcb23f5f72e8c6761c146ef` |

As 40 hipóteses vazias do treino foram excluídas antes do sampling; nenhuma
linha do `dev_matched` foi excluída. O dataset A/B/C continuou selado até
`training_summary.json` estar `COMPLETE`, `selection.json` existir e o
validador independente aprovar a seleção.

### Ordem índice → rótulo

Quatro sondas inequívocas foram executadas depois da seleção. A única
permutação compatível com todos os argmax foi:

| Índice | Rótulo empírico |
|---:|---|
| 0 | entailment |
| 1 | neutral |
| 2 | contradiction |

As sondas cobriram identidade, negação direta, refutação explícita e tópicos
sem relação. Probabilidades do argmax: 0,991987 para entailment; 0,995719 e
0,986780 para contradiction; 0,946774 para neutral. O `id2label` do config foi
registrado, mas não usado como evidência.

### Avaliação adversarial única pós-seleção

`build/adversarial_evaluation.json` foi criado **uma única vez**, usando sem
edição `spikes/07-nli-ptbr-negacao/dataset.py`. Não houve ajuste de modelo,
threshold ou dataset após observar o resultado.

| Modelo | Grupo A | Grupo B | A+B | Terra plana + vacina | Claims curtos estáveis |
|---|---:|---:|---:|---:|---:|
| L6 atual | 2/10 | 3/5 | 5/15 | 0/6 | 1/3 |
| BERTimbau-large + PLUE | 8/10 | 4/5 | 12/15 | 6/6 | **3/3** |
| **BERTimbau-base + PLUE, novo** | **8/10** | **5/5** | **13/15** | **6/6** | 2/3 |

O base melhora o total e o Grupo B e preserva a correção dos seis casos de dano
materializado. Os dois erros restantes são os mesmos semanticamente difíceis:

| Fonte | Esperado | Previsto | P(ent) | P(neu) | P(con) |
|---|---|---|---:|---:|---:|
| Metrópoles — “forma inovadora de tratar” | neutral | entailment | 0,866444 | 0,044731 | 0,088824 |
| G1/Fantástico — “médico ... diz curar” | neutral | entailment | 0,892064 | 0,075320 | 0,032617 |

Há uma regressão material em claims curtos: a família Terra plana deixou de ser
estável. Acertou 3/5 variantes; `Terra plana` foi entailment (0,451336 contra
0,424574 neutral) e a variante com “NASA esconde” foi neutral (0,666252). As
famílias vacina/infarto (4/4) e desemprego (3/3) ficaram estáveis e corretas.
Não havia gate numérico predefinido para essa submétrica, então ela é registrada
como limitação de qualidade a decidir, não ocultada nem usada para retreino.

### Conversão Core ML e paridade no Mac

Foi convertido somente o checkpoint selecionado:

| Propriedade | Valor |
|---|---|
| Formato | Core ML MLProgram |
| Shape | `RangeDim(1...512)`, default 32 |
| Entradas | `input_ids`, `attention_mask`, `token_type_ids` |
| Quantização/compute | pesos INT8 linear symmetric; compute FP16 |
| Compute de validação | `.cpuOnly` |
| Parâmetros | 108.925.443 |
| `.mlpackage` | 104,42 MiB (106.932 KiB em disco) |

Paridade PyTorch → Core ML no Mac: cosseno mínimo **0,9998846191** e argmax
igual em **3/3** sondas. Resultado: **PASS**.

Hashes dos arquivos do pacote:

- `model.mlmodel`: `0768819df9a74797bd7aedaac16f99c13f9194adc9cc8b9c590e8e07c0dc50c6`;
- `weight.bin`: `8153a2b3aace8be194a1dd5577191a9f24980947f6d382935c26bbccdd5e2ac2`;
- `Manifest.json`: `0f3b5188ae13e01046636c582b2b26c41081d3fbeb862d2992533a363f0e422f`.

### Gate físico — PASS

Device detectado: **iPhone 16 (`iPhone17,3`) físico**, iOS **26.3.1 (a)**,
128 GB, identificador CoreDevice
`EFEE75FC-18B6-5948-BC37-9F9A6AA0C0F8`. O build Release `.cpuOnly` passou e
o app de medição tem **219 MB**.

Tentativa 1: a instalação falhou com `IXRemoteErrorDomain code 6`. O harness
truncava a saída e continuava; ele foi corrigido para preservar a saída inteira,
tentar uma vez após falha transitória e abortar corretamente. Também passou a
arquivar o log anterior antes de cada nova execução. Nenhum dado do usuário foi
removido.

Tentativa 2: o app foi instalado com sucesso, mas o preflight não pôde ser
lançado porque o iPhone estava bloqueado:

```text
Unable to launch com.spike.architecturegate9 because the device was not,
or could not be, unlocked. (FBSOpenApplicationErrorDomain error 7: Locked)
```

Tentativa 3: o aparelho foi desbloqueado e confirmou `unlockedSinceBoot: true`,
mas, durante o build para device, a conexão sem fio caiu. O destino passou a
reportar erro de preparação na LAN e depois `tunnelState: unavailable` / device
`unavailable`. Não houve instalação nem medição nesta tentativa.

Tentativa 4: com o iPhone novamente conectado e desbloqueado, o harness
completou todas as fases. Preflight: **2.664 MB livres** depois de instalar o
app de medição; mínimo observado até o fim: **2.578 MB**. Ambos ficam muito
acima do piso conservador de 800 MB e do nível de 626 MB que contaminou o Spike
8. A rodada é comparável.

| Medida `.cpuOnly`, dois modelos vivos | Resultado |
|---|---:|
| App de medição | 219 MB |
| Maior residente observado, qualquer fase | **383,7 MB** |
| Maior footprint observado, qualquer fase | 30,3 MB |
| Carga obrigatória: 180 embeddings + 15 NLI | 294,3 MB residente; 20,2 MB footprint |
| Segunda verificação completa | 294,3 MB residente; sem crescimento |
| 15 pares reais, mediana por par | 21,2 ms |

Para não transformar a divergência de métricas em um passe artificial, a NF-06
usa o número mais conservador, residente: **383,7 MB**, com pelo menos **640,3
MB de margem** até 1.024 MB. Resultado NF-06: **PASS com margem material**.

| Tokens | Frio (1 par) | Aquecido (mediana de 9) | Pico residente |
|---:|---:|---:|---:|
| 77 | 20,2 ms | 14,1 ms | 213,4 MB |
| 128 | 25,1 ms | 18,7 ms | 205,8 MB |
| 256 | 39,2 ms | 32,6 ms | 208,5 MB |
| 384 | 56,5 ms | 49,2 ms | 213,5 MB |
| 512 | **76,7 ms** | **66,5 ms** | **220,2 MB** |

Resultado NF-02: **PASS**. Mesmo o primeiro par de 512 tokens é 13 vezes mais
rápido que o teto de 1 s; a mediana aquecida é 15 vezes mais rápida.

A paridade Mac → iPhone passou 3/3: cosseno **1,000000** e argmax idêntico nas
sondas entailment, contradiction e neutral. O modelo foi usado com
`input_ids`, `attention_mask` e `token_type_ids`; nenhuma entrada foi omitida.

O app descartável `com.spike.architecturegate9` foi desinstalado ao fim da
rodada. Não foi usado simulador e nenhum dado do usuário foi apagado. O log
bruto final está em `trained_device_results_iphone.log`; o resumo estruturado
está em `build/trained_gate_summary.json`.

### Comparação consolidada para decisão

| Modelo | Pares reais | Casos críticos | Claims curtos estáveis | Pacote NLI | RAM/latência no device |
|---|---:|---:|---:|---:|---|
| L6 atual | 5/15 | 0/6 | 1/3 | ~103 MB | 2 ms; RAM comparável não disponível |
| BERTimbau-large + PLUE | 12/15 | 6/6 | 3/3 | 320,1 MB | reprova: 1.875 MB residente / 3.488 ms a 512 |
| **BERTimbau-base + PLUE** | **13/15** | **6/6** | 2/3 | **104,42 MiB** | **383,7 MB** residente máx.; **66,5 ms** a 512 |

### Decisão consolidada dos gates

| Gate | Resultado |
|---|---|
| Treino completo e integridade | PASS |
| Seleção exclusivamente por PLUE | PASS — época 3 |
| Ordem índice→rótulo única | PASS |
| Qualidade: pares reais / casos críticos | PASS com limitação — 13/15 e 6/6; claims curtos 2/3 |
| Conversão e paridade no Mac | PASS |
| Espaço livre antes da medição | PASS — 2.664 MB no preflight; mínimo 2.578 MB |
| NF-06 RAM física | PASS — máximo residente 383,7 MB |
| NF-02 latência física | PASS — 66,5 ms aquecido e 76,7 ms frio a 512 |
| Paridade Mac→iPhone | PASS — cosseno 1,0; argmax 3/3 |
| Integração no app | NÃO INICIADA |

**Decisão da Etapa 3: PASS nos gates explícitos.** O checkpoint BERTimbau-base
fine-tuned é tecnicamente elegível para substituir o NLI atual: corrige 6/6
casos críticos, passa RAM/latência com ampla margem e preserva paridade no
device. A regressão de estabilidade de claims curtos (2/3 versus 3/3 no large)
permanece uma limitação conhecida a ser tratada como risco de produto, sem
ajuste pós-hoc. A integração continua proibida até OK explícito do usuário.

### Comandos reproduzíveis

```bash
# Validar treino e seleção apenas por PLUE
spikes/02-coreml-latencia/.venv/bin/python \
  spikes/09-nli-base-search/validate_training_result.py

# Executar somente se adversarial_evaluation.json ainda não existir
spikes/02-coreml-latencia/.venv/bin/python \
  spikes/09-nli-base-search/evaluate_adversarial.py

# Converter somente checkpoint-best selecionado
spikes/02-coreml-latencia/.venv/bin/python \
  spikes/09-nli-base-search/convert_trained_model.py

# Com iPhone conectado e desbloqueado: preflight + gate físico
bash spikes/09-nli-base-search/run_trained_device_gate.sh

# Consolidar as GATELINEs após uma execução física completa
spikes/02-coreml-latencia/.venv/bin/python \
  spikes/09-nli-base-search/summarize_gate.py \
  --log spikes/09-nli-base-search/trained_device_results_iphone.log \
  --output spikes/09-nli-base-search/build/trained_gate_summary.json
```

### Artefatos principais

| Artefato | Conteúdo |
|---|---|
| `build/training-full/training_summary.json` | resumo COMPLETE e melhor validação |
| `build/training_validation.json` | validação independente, hashes e métricas das épocas |
| `build/adversarial_evaluation.json` | única execução das sondas e A/B/C |
| `build/trained/conversion_manifest.json` | parâmetros, shape, quantização e paridade Mac |
| `build/trained/bertimbau_base_plue_dynamic512_int8.mlpackage` | modelo convertido |
| `trained_device_results_iphone.log` | build/instalação e bloqueio físico bruto |
| `run_trained_device_gate.sh` | harness físico com retry/abort correto de instalação |
