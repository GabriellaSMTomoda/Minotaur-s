# Spike 7 — RESULTADO

**Data:** 03/08/2026
**Endereça:** item aberto 24 (bloqueia lançamento) e item aberto 25 da spec.
**Escopo:** medir. Nada em DT-18, DT-26, DT-29 ou RF-07.x foi alterado, e o
caminho (b) não foi implementado no app.

---

## Resumo

**Caminho (a) — modelos NLI com base nativa de PT-BR: achado forte, e o
candidato passa o gate de execução.**
`giotvr/bertimbau_large_plue_mnli_fine_tuned` (BERTimbau-large fine-tunado em
MNLI traduzido) acerta **12/15** dos pares reais contra **5/15** do modelo em
produção, é o **único** dos quatro modelos testados que fica estável nas três
famílias de claim curto (3/3), e acerta **todos** os casos de Terra plana e de
vacina — os dois que hoje viram `CONFIRMADO` em produção. Executa em device
físico em **`.cpuOnly`**, a mesma configuração que o `NLIService` usa hoje, com
logits idênticos ao PyTorch (cos = 1,0), **40,3 ms** por par e **643 MB** de
pico. Custa 320 MB de bundle (contra 103 MB) e exige duas mudanças reais de
integração: `token_type_ids` como terceira entrada e um tokenizador WordPiece
no app.

**Caminho (b) — verificação por negação: não funciona. Recupera zero casos.**
A leitura (i) (simetria) **nunca disparou**: 0 vezes, em 4 modelos × 5 limiares ×
2 fontes de negação. A premissa da hipótese — "o chunk sustenta tanto X quanto
não-X" — é empiricamente falsa: os modelos são confiantemente assimétricos
mesmo quando erram. A leitura (ii) (diferencial) **nunca superou** o argmax
direto em nenhum modelo. E gerar a negação em PT-BR on-device acerta 8/14, com a
falha caindo justamente sobre "Vacina da gripe causa infarto." — um dos três
claims que falharam em produção.

**Achado estrutural do caminho (a), que vale registrar mesmo que nada mude:** o
corpus de NLI em português mais usado (ASSIN2) **não tem classe de
contradição** — é RTE binário (`ENTAILMENT`/`NONE`). Isso elimina de saída a
maior parte da família PT-BR: um modelo treinado nele nunca produziria o
veredito `CONTRADITO` da RF-08.3.

Recomendação e trade-offs no fim.

---

## Conjunto de teste

Todo o texto é **real**, recuperado da investigação instrumentada pós-Fase 5
(pipeline real: proxy no ar, `URLSession` de verdade, os dois `.mlpackage` do
bundle em `.cpuOnly`). Nenhum par foi construído para caber numa regra.
Declarado em [`dataset.py`](./dataset.py).

| Grupo | O que é | N |
|---|---|---|
| **A** | Os 10 pares adversariais que separaram os modelos na investigação: 8 falhas reais + 2 controles que o pipeline acertou | 10 |
| **B** | Chunks adicionais dos **mesmos 3 claims que falharam em produção** ("A Terra é plana.", "Vacina da gripe causa infarto.", "Brasileiro encontrou cura do câncer."), incluindo o único que o pipeline acertou (O Globo, "não existe base científica") | 5 |
| **C** | Claims curtos de frase única — item aberto 25. 3 famílias × 3–5 redações do **mesmo** fato. Mede acerto **e estabilidade**: o rótulo deve ser o mesmo entre as redações | 12 |

Os 3 claims de produção estão distribuídos entre A e B; não são um grupo à
parte porque cada um só existe como par com um chunk real de artigo.

**Validação da reconstrução:** o modelo em produção (`L6`) marca **2/10** no
grupo A neste spike — exatamente o número do relatório da investigação. O
conjunto é o mesmo.

---

## Caminho (a) — modelos com base nativa de PT-BR

### FILTRO 0 — reprovados antes de baixar peso

Aplicado por leitura de `config.json` e model card. A razão de reprovação é o
achado mais importante deste caminho.

| Candidato | Base | Motivo |
|---|---|---|
| `ruanchaves/bert-base-portuguese-cased-assin2-entailment` | BERTimbau-base | `num_labels=2`. ASSIN2 é RTE **binário** (`ENTAILMENT`/`NONE`) — sem classe de contradição, o veredito `CONTRADITO` (RF-08.3) fica inalcançável |
| `ruanchaves/bert-large-portuguese-cased-assin2-entailment` | BERTimbau-large | idem |
| `giotvr/bertimbau_large_assin2_fine_tuned` | BERTimbau-large | 3 saídas no config, mas o model card define a função de inferência como `ENTAILMENT`/`NONE`; a 3ª saída é herança do setup de ASSIN v1 (entailment/paraphrase/none) |
| `giotvr/xlm_roberta_base_assin2_fine_tuned` | XLM-R-base | idem — e a base nem é PT-BR |
| `sagui-nlp/debertinha-ptbr-xsmall-assin2-rte` | DeBERTinha (DeBERTa-v3 PT-BR) | duplo: ASSIN2 binário **e** atenção desemaranhada (XSoftmax + posição relativa) — a mesma operação não-padrão que fez o mDeBERTa converter e não executar (Spike 2). Reprovado cedo, por decisão explícita de não repetir aquele ciclo |
| `ricardo-filho/bert-base-portuguese-cased-nli-assin-2` | BERTimbau-base | `architectures=['BertModel']` — é sentence-transformer, produz embedding, não distribuição NLI |
| `nicholasKluge/TeenyTinyLlama-460m-Assin2` | TeenyTinyLlama-460m | ASSIN2 binário + 460M parâmetros em decoder |

**Consequência:** a família "BERTimbau + ASSIN2", que é o alvo óbvio de uma busca
por NLI em português, é inutilizável para este produto. Os candidatos que
sobraram são os treinados em corpus de 3 classes — InferBR (nativo) e PLUE/MNLI
(MNLI traduzido).

### Confirmação da ordem índice→rótulo (bloqueante)

Dois dos três candidatos trazem `id2label` genérico. A ordem veio do model card
e foi **confirmada empiricamente** com 4 sondas inequívocas antes de qualquer
medição — trocar `entailment` por `contradiction` inverteria o veredito sem erro
visível em lugar nenhum. Todos os 4 modelos: **4/4, ordem confirmada**
([`probe_labels.py`](./probe_labels.py)).

### FILTRO 1 — conversão Core ML INT8

| Modelo | INT8 | Tokenizador | `token_type_ids` | cos vs. PyTorch (desktop) |
|---|---|---|---|---|
| `inferbr` (BERTimbau-large + InferBR) | **320,1 MB** | WordPiece (`BertTokenizerFast`) | **sim** | 1,0 ✅ |
| `plue_bertimbau` (BERTimbau-large + PLUE/MNLI) | **320,1 MB** | WordPiece (`BertTokenizerFast`) | **sim** | 1,0 ✅ |
| `plue_xlmr` (XLM-R-base + PLUE/MNLI, controle) | **266,4 MB** | SentencePiece (`XLMRobertaTokenizerFast`) | não | 1,0 ✅ |

Nenhum precisou de custom op ou monkeypatch — o perfil "BERT clássico, atenção
padrão" converteu limpo, como previsto em [`candidates.py`](./candidates.py)
antes de testar.

**Custo de integração que a tabela esconde:** BERT usa `token_type_ids` para
separar premissa de hipótese. O `NLIService` e o `XLMRTokenizer` do app
produzem apenas `input_ids` + `attention_mask`. Adotar um candidato BERT exige
uma **terceira entrada** no modelo e um **tokenizador WordPiece** no app — não é
troca de arquivo `.mlpackage`. Converter com `token_type_ids` zerado "para caber
na interface atual" degradaria o modelo silenciosamente, que é a classe de erro
que este spike existe para não repetir.

Um efeito colateral favorável: o vocabulário do BERTimbau tem 29.794 tokens
contra 250.002 do XLM-R, então o `NLITokenizer.json` cairia dos 17 MB atuais
para ~2 MB — alívio parcial no item aberto 21.

### FILTRO 2 — execução em device físico (iPhone 16, iOS 26.3.1)

O gate que o mDeBERTa não passou. Um modelo por instalação: os três
`.mlpackage` somam ~900 MB e o aparelho não tem espaço para instalá-los juntos.

| Modelo | `.cpuOnly` | `.all` | cos vs. PyTorch | Latência `.cpuOnly` (mediana de 50) | RAM pico `.cpuOnly` |
|---|---|---|---|---|---|
| **`plue_bertimbau`** | ✅ **executa** | ✅ executa (114,8 ms · 1.154 MB) | **1,0** · argmax bate | **40,3 ms** | **643,4 MB** |
| `inferbr` | ✅ **executa** | ⚠️ não medido — disco do device | **1,0** · argmax bate | **40,3 ms** | **643,1 MB** |
| `plue_xlmr` (controle) | ❌ **signal 9** | ❌ **signal 9** | — | — | — |
| `L6` (atual, DT-18, Spike 2c) | ✅ | ✅ (10,5 ms) | 1,0 | **2 ms** | — |

Os dois BERTimbau passam o gate na configuração que importa: **`.cpuOnly`, a
mesma que o `NLIService` usa hoje** (DT-18). Como no Spike 2c, `.cpuOnly` é
**mais rápido** que `.all` neste perfil (40,3 ms contra 114,8 ms) e gasta bem
menos memória (643 MB contra 1.154 MB) — shape dinâmico `RangeDim` continua não
aproveitando a ANE.

**40,3 ms contra 2 ms** é 20× mais lento que o modelo atual. Cabe folgado em
NF-02 (< 1 s por par); com 5 artigos × até 3 chunks dá ~0,6 s de NLI numa
verificação, dentro da NF-03 (< 15 s).

**Ressalva honesta sobre este filtro — o aparelho estava com pouco
armazenamento** (~300 MB livres), e isso contaminou parte das tentativas:

- a primeira tentativa de instalar os três modelos juntos falhou por espaço
  (`IXUserPresentableErrorDomain 11`), o que motivou o modo um-por-vez;
- a **primeira** execução de `plue_bertimbau` em `.cpuOnly` morreu por signal 9;
  a repetição, com o aparelho menos pressionado, rodou normalmente e produziu os
  números da tabela. O resultado reportado é o da execução limpa, e o registro
  da falha fica aqui de propósito;
- `.all` de `inferbr` e a repetição de `.all` de `plue_bertimbau` abortaram com
  `LLVM ERROR: IO failure on output stream: No space left on device` — a
  compilação para ANE precisa escrever em disco. É limitação do aparelho, não
  do modelo. O número de `.all` do `plue_bertimbau` vem da execução em que
  ainda havia espaço.

O **`plue_xlmr` é a exceção que não parece ambiental**: morreu por signal 9 nas
duas configurações, em duas tentativas separadas, sempre em ~4 segundos — morte
no carregamento, não depois de trabalho. Ele é **controle**, não candidato de
produto, e o papel dele no spike (separar "base em português" de "fine-tune em
português") já foi cumprido em PyTorch. Fica reprovado no FILTRO 2 e registrado
como tal.

---

## FILTRO 3 — qualidade PT-BR

Medido em PyTorch fp32 no desktop, para separar "o modelo julga mal" de "algo no
caminho está errado" — a paridade Core ML×PyTorch é assunto do FILTRO 2, e deu
1,0 em todos.

| Modelo | Grupo A (10) | Grupo B (5) | **Pares reais (15)** | Claims curtos: grupos estáveis (3) |
|---|---|---|---|---|
| **`L6` — atual (DT-18)** | 2/10 | 3/5 | **5/15** | **1/3** |
| `inferbr` — BERTimbau-large + InferBR | 5/10 | 4/5 | **9/15** | 2/3 |
| **`plue_bertimbau` — BERTimbau-large + PLUE/MNLI** | **8/10** | 4/5 | **12/15** | **3/3** |
| `plue_xlmr` — XLM-R-base + PLUE/MNLI (controle, reprovado no FILTRO 2) | 5/10 | 4/5 | **9/15** | 3/3 |

O `plue_xlmr` aparece aqui apesar de ter sido reprovado no FILTRO 2 porque a
função dele é responder uma pergunta que só se responde em PyTorch — ver abaixo.
Ele não é candidato de produto.

### O que cada um ainda erra

- **`L6` (atual)** erra os 10: todos os de Terra plana, todos os de vacina,
  todos os de câncer. Inclusive lê o título *"Vacina da gripe reduz de 20 a 30%
  a incidência de infarto"* como `entailment` de "Vacina da gripe causa
  infarto.".
- **`inferbr`** conserta **todo** o caso da vacina, mas continua respondendo
  `entailment` para os três chunks de Terra plana — o mesmo modo de falha do L6.
  Dataset nativo de PT-BR não bastou.
- **`plue_bertimbau`** acerta **Terra plana (3/3) e vacina (3/3)** — os dois
  casos que hoje produzem `CONFIRMADO` em produção. Seus 3 erros são **todos**
  do caso "Brasileiro encontrou cura do câncer", que exige distinguir
  *tratar*/*diz curar*/*remissão de um paciente* de *encontrou a cura* — perda
  de quantificador e de modalidade, o mais difícil do conjunto. É também o
  **único** modelo que acerta o chunk do O Globo ("não existe base científica")
  como `contradiction`.
- **`plue_xlmr` (controle)** responde a pergunta que o resto do spike não
  responderia: **o ganho vem da base em português, não só do fine-tune em PT.**
  Mesmo corpus do `plue_bertimbau`, base multilíngue → 9/15 contra 12/15, e
  volta a errar Terra plana (vira `neutral`) e o título da CNN sobre vacina.

### Item aberto 25 — claims curtos

| Modelo | terra-plana (5 redações) | vacina-infarto (4) | desemprego (3) |
|---|---|---|---|
| `L6` | instável — 1/5 correto | — | — |
| `inferbr` | **instável** — `[ent, ent, ent, con, neu]`, 1/5 | estável 4/4 | estável 3/3 |
| `plue_bertimbau` | **estável 5/5** | estável 4/4 | estável 3/3 |
| `plue_xlmr` | estável, mas **0/5** (tudo `neutral`) | estável 4/4 | estável 3/3 |

A oscilação relatada no item 25 ("A Terra é plana." → `CONFIRMADO`; "…e a NASA
esconde isso das pessoas." → `DIVERGENTES`) **reproduz** no `L6` e no `inferbr`,
e **desaparece** no `plue_bertimbau`, que dá `contradiction` nas cinco redações,
inclusive em "Terra plana" sem verbo e sem ponto. Estabilidade e acurácia
andaram juntas: o modelo que julga melhor também oscila menos.

---

## Caminho (b) — verificação por negação

Duas leituras do sinal, medidas separadamente, com duas fontes de negação
(manual e automática). [`negacao.py`](./negacao.py).

### Leitura (i) — simetria: **nunca disparou**

A regra era: se o chunk sustenta tanto X quanto ¬X, vira `neutral`.

| Disparos de `min(P(ent\|X), P(ent\|¬X)) ≥ tau` | tau=0,50 | 0,60 | 0,70 | 0,80 | 0,90 |
|---|---|---|---|---|---|
| `L6`, `inferbr`, `plue_bertimbau`, `plue_xlmr` — manual **e** auto | **0** | **0** | **0** | **0** | **0** |

Zero disparos em 4 modelos × 5 limiares × 2 fontes. **A premissa da hipótese é
empiricamente falsa.** Os modelos não sustentam X e ¬X ao mesmo tempo: negar a
hipótese derruba `P(entailment)` com força mesmo quando a resposta direta está
errada. Nos três chunks de Terra plana no `inferbr`, por exemplo,
`P(ent|X)=1,000` e `P(ent|¬X)=0,007/0,014/0,001` — assimetria máxima, e ainda
assim o rótulo direto está errado. O modelo não está "indeciso": está
confiantemente errado, e a negação confirma o mesmo erro com o sinal invertido.

### Leitura (ii) — diferencial: **nunca superou o argmax direto**

| Modelo | base (argmax direto) | melhor diferencial (qualquer delta) |
|---|---|---|
| `L6` | 5/15 | 4/15 |
| `inferbr` | 9/15 | 8/15 |
| `plue_bertimbau` | 12/15 | 10/15 |
| `plue_xlmr` | 9/15 | 5/15 |

Em nenhum modelo, em nenhum dos 6 valores de delta, a regra diferencial empatou
sequer com a decisão direta. Ela destrói `neutral` como categoria — a diferença
entre `P(ent|X)` e `P(ent|¬X)` quase nunca cai na faixa central — e transforma
neutros corretos em direcionais errados.

### Custo de gerar a negação em PT-BR — parte do resultado

Negador on-device com `NLTagger` ([`negador/negador.swift`](./negador/negador.swift)),
a mesma ferramenta que o `ChunkQualityFilter` e o `TextChunker` já usam. Sem LLM
(§5 proíbe), sem rede (NF-07). Regra: se já é negativa, remove a marca; senão,
insere "não" antes do primeiro verbo finito.

**8 de 14 claims corretos.** Os erros:

| Claim | Saída | Problema |
|---|---|---|
| **"Vacina da gripe causa infarto."** | *(falhou)* | `NLTagger` não marca **"causa"** como verbo — é homógrafo do substantivo. **Um dos 3 claims que falharam em produção não é negável** |
| "Vacina da gripe causa infarto" (sem ponto) | *(falhou)* | idem |
| "Terra plana" | *(falhou)* | genuinamente sem verbo — sintagma nominal, e é redação plausível de usuário |
| "Tomar a vacina da gripe provoca ataque cardíaco." | "**não Tomar** a vacina da gripe provoca ataque cardíaco." | negou o infinitivo do sujeito em vez do verbo principal; agramatical e com sentido trocado |
| "A Terra é plana e a NASA esconde isso das pessoas." | "A Terra **não** é plana e a NASA esconde isso das pessoas." | nega só a primeira conjunta: ¬(A∧B) ≠ (¬A)∧B |
| "Cientistas confirmaram que a Terra é plana." | "Cientistas **não** confirmaram que a Terra é plana." | nega a atribuição de fala, não a proposição sob verificação |

Os três últimos são o mesmo problema de fundo: **negar corretamente exige saber
qual é a proposição principal**, e isso é análise sintática, não uma regra de
inserção. O efeito aparece nos números: com negação manual o `inferbr` mede 15
pares; com a automática, 11 (4 pulados por falha) e a base cai de 9/15 para
5/11.

A classificação "correto/parcial/errado" acima é julgamento meu, caso a caso,
com o motivo declarado — não uma métrica automática.

---

## Recomendação

**Não adotar o caminho (b).** O resultado é negativo e não é questão de
calibragem: a leitura (i) não dispara nenhuma vez e a leitura (ii) piora todos
os modelos. Some-se que a negação sequer é gerável para um dos claims de
produção. Não recomendo insistir em variantes desta técnica sem uma hipótese
nova — o custo de dobrar a inferência não compra nada aqui.

**Levar o caminho (a) adiante: `plue_bertimbau` é o candidato.** É o primeiro
modelo testado que conserta os dois casos que hoje produzem dano informacional
ativo (Terra plana, vacina), o único estável nas três famílias de claim curto, e
passa o gate de execução em `.cpuOnly` com logits idênticos ao PyTorch. A
decisão de trocar DT-18 é sua; o que este spike entrega é que a troca agora tem
um candidato que **de fato roda**, o que não era verdade nem para o mDeBERTa
(100% em pares limpos, não executa) nem para o `symanto` (executa, 5/10).

Antes de decidir, duas medições que faltam e que eu não fiz porque saem do
escopo de spike e entram em integração:

1. **RAM ponta a ponta.** Os 643 MB são do harness rodando **só** o NLI. O app
   carrega também os 113 MB de embeddings. NF-06 dá 1 GB de teto; a folga
   existe, mas não foi medida com os dois modelos vivos ao mesmo tempo. É a
   primeira coisa a verificar se a troca for aprovada.
2. **`.all` num aparelho com espaço.** Não é bloqueante — `.cpuOnly` é a
   configuração escolhida e a mais rápida —, mas as duas tentativas de `.all`
   abortaram por disco, então esse número está incompleto.

E um caminho alternativo, se o custo de 320 MB e da reintegração pesar demais:
**procurar (ou treinar) um BERTimbau-*base* com cabeça NLI de 3 classes.** O
controle `plue_xlmr` mostra que o ganho vem da base em português, e todo o custo
vem de ser *large*. Não existe checkpoint público assim hoje — os de
BERTimbau-base são ASSIN2, binários —, então isso significaria fine-tune
próprio: trabalho de treino, não de conversão, fora de tudo que a spec previu
até aqui.

### Trade-offs, explicitamente

| | Manter DT-18 (`L6`) | Trocar por `plue_bertimbau` |
|---|---|---|
| Pares reais | 5/15 | **12/15** |
| Terra plana / vacina (os casos de dano) | 0/6 | **6/6** |
| Claims curtos estáveis (item 25) | 1/3 | **3/3** |
| Executa em `.cpuOnly` (config do app) | ✅ 2 ms | ✅ **40,3 ms** |
| RAM de pico (só o NLI) | não medido no Spike 2c | 643 MB — dentro da NF-06, **falta medir com os dois modelos** |
| Tamanho INT8 | 103 MB | **320 MB** (com embeddings: 433 MB, dentro do alvo de 500 MB da NF-05) |
| `NLITokenizer.json` | 17 MB (XLM-R, vocab 250k) | **~2 MB** (WordPiece, vocab 29,8k) — alívio no item 21 |
| Trabalho de integração | — | `token_type_ids` como 3ª entrada + tokenizador WordPiece no app + novas fixtures de paridade |
| O que continua errando | tudo, inclusive títulos que dizem o oposto | só o caso "cura do câncer" (modalidade/quantificador) |

**O que já está resolvido independentemente disto:** a DT-33 (limpeza de chunks)
foi implementada e testada no app. Ela some com o ruído de byline/navegação/
título de página, mas — como a própria DT-33 registra — não move nenhum dos
casos acima, porque neles a premissa já era um parágrafo legítimo.

---

## Arquivos

| Arquivo | O que é |
|---|---|
| [`candidates.py`](./candidates.py) | Candidatos, triagem do FILTRO 0 e ordem dos filtros |
| [`dataset.py`](./dataset.py) | Conjunto de teste (grupos A/B/C + negações manuais) |
| [`probe_labels.py`](./probe_labels.py) | Confirmação empírica da ordem índice→rótulo |
| [`convert_and_reference.py`](./convert_and_reference.py) | FILTRO 0+1: conversão INT8 + referência PyTorch |
| [`run_gate_device.sh`](./run_gate_device.sh) + [`xcode-bench/`](./xcode-bench) | FILTRO 2: execução em device físico |
| [`qualidade_ptbr.py`](./qualidade_ptbr.py) | FILTRO 3: qualidade PT-BR |
| [`negacao.py`](./negacao.py), [`negador/negador.swift`](./negador/negador.swift) | Caminho (b) |
| `build/*.json` | Saídas brutas de cada etapa (não versionadas) |
| `device_results_iphone.log` | `BENCHLINE`s crus do device |
