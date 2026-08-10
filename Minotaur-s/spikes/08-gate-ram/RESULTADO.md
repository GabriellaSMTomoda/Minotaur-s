# Spike 8 — RESULTADO

**Data:** 03/08/2026
**Endereça:** item aberto 27 — **GATE DA FASE 6**. Pico de RAM ponta a ponta com os
dois modelos vivos ao mesmo tempo, contra o teto de 1 GB da NF-06.
**Escopo:** medir. Nenhum arquivo do app foi tocado. DT-18, DT-26, DT-29 e o desenho do
`VerificationPipeline` estão exatamente como estavam.

---

## Veredito

**O gate REPROVA.** Com os dois modelos vivos e a carga de uma verificação real
(180 embeddings + 15 pares de NLI), o pico é de **1.125 MB de footprint** — 10% acima
do teto de 1 GB da NF-06, sem margem nenhuma. E antes disso, só de **carregar** os dois
modelos, há um transiente de **1.314 MB**, antes de qualquer inferência.

**E a mitigação prevista no item 27 não resolve.** Descarregar o modelo de embeddings
antes do NLI foi medido: recupera **2 MB**. O modelo de embeddings não é o que custa —
custa 28 MB de footprint carregado e +2 MB rodando os 180 chunks. Os ~1.100 MB são do
`plue_bertimbau` sozinho.

| Cenário (carga real, 5 artigos) | Pico footprint | Pico resident | Teto NF-06 |
|---|---|---|---|
| Carregar os dois modelos (antes de inferir) | **1.314 MB** | 1.660 MB | ❌ |
| 180 embeddings reais | 696 MB | 815 MB | ✅ |
| 15 pares de NLI reais | **1.125 MB** | 1.224 MB | ❌ |
| Segunda verificação seguida | 1.131 MB | 1.231 MB | ❌ |
| Idem, soltando embeddings antes do NLI | **1.130 MB** | 1.174 MB | ❌ |
| Um único comprimento de sequência | 1.001 MB | 1.086 MB | ⚠️ no limite |
| Pior caso — tudo a 512 tokens | **1.760 MB** | 1.875 MB | ❌ |

Reprova nas duas métricas, então o veredito não depende de qual delas se escolhe olhar.

---

## Como foi medido

Harness iOS próprio (`xcode-bench/`), rodando em **iPhone 16 físico, iOS 26.3.1**, com os
dois `.mlpackage` compilados pelo Xcode no build (`.mlmodelc` no bundle) e carregados em
**`.cpuOnly`** — a configuração do app (DT-18) e a mesma que o Spike 7 mediu. Simulador
não serve: lá a memória é a do Mac, com outro alocador e sem jetsam.

**Os dois modelos ficam vivos do começo ao fim**, que é o que o
`VerificationPipeline.loadFromBundle` faz hoje: constrói `EmbeddingService` e `NLIService`
juntos e os mantém pela vida da tela.

**Duas métricas de memória**, de propósito:

- `resident_size` — a que o Spike 7 usou para reportar os 643 MB. Está aqui só para os
  números serem comparáveis com aquele relatório.
- `phys_footprint` — a que o iOS de fato cobra e o jetsam olha. **O veredito sai dela.**

Amostradas a cada 3 ms numa thread própria: o pico acontece dentro de uma `predict()`, e
medir só antes e depois perderia exatamente o instante que interessa.

**Um cenário por lançamento, em processo novo.** Memória de Core ML é pegajosa — a
primeira rodada mediu tudo num processo só e não soube dizer se o crescimento vinha dos
embeddings ou do NLI. Refazer com fases isoladas é o que produziu a tabela acima.

### A carga é real

`make_fixture.py` produz as sequências a partir de **texto de artigo real** — HTML baixado
no Spike 3, de 6 domínios da allowlist (Estadão, Band, DW, AP, Terra, Senado) —, chunkado
pelas regras do `TextChunker` (parágrafo + sobreposição de 1 frase + mesmo orçamento de
tokens) e tokenizado pelos **tokenizadores reais** dos dois modelos. Os 15 pares usam os
3 claims que falharam em produção como hipótese.

| | N | mín | mediana/média | máx |
|---|---|---|---|---|
| Chunks (embeddings, XLM-R) | 180 | 16 tok | 98 tok | 216 tok |
| Pares (NLI, WordPiece + `token_type_ids`) | 15 | 135 tok | 167 tok | 241 tok |

O harness recebe ids, não texto: o tokenizador WordPiece em Swift é trabalho da Etapa 2, e
o custo de RAM de uma predição é função do **comprimento** da sequência, não de quais ids
ela carrega. O que precisava ser real — os comprimentos — é real.

### O harness está alimentando o modelo direito

Os logits do device para o 1º par batem com o PyTorch fp32: **cos = 0,999986**, argmax
igual ([`check_parity.py`](./check_parity.py)).

| | logits |
|---|---|
| PyTorch fp32 | `[-1,922, -0,239, 1,892]` |
| Core ML no device | `[-1,921, -0,225, 1,883]` |
| **Sem `token_type_ids`** (sonda) | `[-2,072, -0,399, 2,932]` |

A terceira linha é o modo de falha que o Spike 7 mandou não repetir: alimentar o BERT sem
`token_type_ids` roda e devolve outro número, sem erro nenhum. A medição acima é de um
modelo rodando certo, com a interface de 3 entradas que a Etapa 2 vai integrar.

---

## Para onde vai a memória

**INT8 economiza disco, não RAM.** O `plue_bertimbau` é BERT-large: hidden 1024, 24
camadas, vocab 29.794 → **~333 M parâmetros**. Em fp16 isso dá ~666 MB de peso, e é o que
se mede: o footprint logo depois de carregar os dois modelos é **693,6 MB**, com o de
embeddings respondendo por 28 MB. Os 320 MB do arquivo `.mlpackage` são o tamanho **em
disco**; no caminho de CPU os pesos são materializados em ponto flutuante.

Isso explica também o transiente de 1.314 MB no carregamento: as duas formas coexistem
enquanto o modelo é preparado.

**O resto é ativação e especialização por shape.** Os 15 pares levam o footprint de 694 MB
a 1.013 MB estáveis, com pico de 1.125 MB. Rodando **um único comprimento** de sequência o
pico cai para 1.001 MB — ou seja, **~124 MB do pico vêm da variedade de comprimentos**: os
modelos foram convertidos com `RangeDim`, cada comprimento novo é um shape novo, e o Core
ML guarda a especialização de cada um. Mesmo assim, 1.001 MB é o teto inteiro sem folga.

**Não é vazamento.** A segunda verificação seguida não cresce (1.131 MB contra 1.125 MB), e
depois do pior caso o footprint volta de 1.752 MB para 1.058 MB. É patamar, não escada.

---

## Achados colaterais (fora do que o gate perguntou)

1. **NF-02 estoura no pior caso.** A latência do NLI cresce com o quadrado do
   comprimento: **40 ms** a 77 tokens (Spike 7), **226 ms** a 167 tokens (aqui, carga
   real), **3.488 ms** a 512 tokens. O limite da NF-02 é 1 s por par. Chunk no orçamento
   cheio (496 tokens) é produzido por qualquer artigo de parágrafos longos — não é caso
   exótico. A carga real completa (180 embeddings + 15 pares) leva **4,7 s** só de
   inferência, contra os ~0,6 s estimados no Spike 7; ainda cabe na NF-03, com menos folga.
2. **O que esta medição NÃO inclui.** Os dois tokenizadores que o app carrega via
   `swift-transformers` (17 MB de JSON cada hoje; ~2 MB o WordPiece depois da troca), o
   SwiftUI e o estado da tela. O pico do app integrado é **maior** que estes números, não
   menor.
3. **Disco do device — a ressalva do FILTRO 2 do Spike 7 continua valendo, e piorou.**
   Ver abaixo.

---

## Ressalva de disco (não contornada, por instrução)

O aparelho reporta **626 MB livres** com o app de medição (537 MB) instalado — ou seja,
~1,16 GB livres sem ele.

Isso não é detalhe de logística: quando o harness foi rebuildado com um terceiro
`.mlpackage` (o modelo atual, para servir de linha de comparação), passando o app de
434 MB para 537 MB, **todas as medições degradaram de forma reprodutível**:

| | app de 434 MB | app de 537 MB |
|---|---|---|
| Footprint ao carregar embeddings | 28 MB | 694 MB |
| Latência por embedding (mediana) | 1,4–4,3 ms | 90–100 ms |
| Pico de footprint na fase de embeddings | 696 MB | **3.375 MB** |
| Desfecho | completa as 3 rodadas | processo **morto** no meio |

Reproduziu em 3 lançamentos. A leitura mais provável é a mesma do Spike 7: o Core ML grava
em disco o plano compilado de cada shape, e sem espaço a especialização acontece em
memória, a cada predição.

**A tabela do veredito usa exclusivamente as medições do build de 434 MB**, que rodou
limpo, com números estáveis entre lançamentos e latências coerentes com o Spike 7. A
comparação com o modelo atual (`L6`) ficou contaminada e **não é reportada como número
confiável** — no mesmo build degradado, a fase de NLI do `L6` picou 533 MB contra 1.385 MB
do `plue_bertimbau`, o que dá a ordem de grandeza da diferença, mas não serve de medida.

Não liberei espaço no aparelho, não apaguei nada e não dividi a instalação para contornar
— foi pedido avisar antes de tentar qualquer coisa nessa direção.

---

## O que este spike NÃO decide

A mitigação. O item 27 previa descarregar o modelo de embeddings antes do NLI; isso foi
**medido** (recupera 2 MB) e por isso está descrito aqui como ineficaz, mas nenhuma
alternativa foi implementada e o desenho do `VerificationPipeline` não foi tocado. As
saídas visíveis nos dados — teto da NF-06, shape fixo por padding, modelo *base* em vez de
*large* (o caminho alternativo que o próprio Spike 7 já registrou) — são decisão do
usuário.

---

## Arquivos

| Arquivo | O que é |
|---|---|
| [`make_fixture.py`](./make_fixture.py) | Carga de trabalho: texto real → chunks → ids dos dois tokenizadores |
| [`check_parity.py`](./check_parity.py) | Sanidade: logits do device × PyTorch, e a sonda de `token_type_ids` |
| [`run_gate_ram.sh`](./run_gate_ram.sh) | Build + install + lançamento por cenário no device |
| [`xcode-bench/`](./xcode-bench) | Harness iOS (`MemoryProbe`, `GateRun`) |
| `build/*.json` | Saídas intermediárias (não versionadas) |
| `device_results_iphone.log` | `RAMLINE`s crus do device |
