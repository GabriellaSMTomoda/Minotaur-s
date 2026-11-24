# Estado da implementação — 24/11/2026 (evidência v3)

## Por que mudou

Na v0.5 o Verificador respondia "Fontes divergentes" até para fatos triviais. O harness offline (`harness/`) reproduziu o problema e mostrou a causa. Uma única passagem com contradição ≥ 0,5, entre até 24 pares, bastava para DIVERGENTE. E o NLI dá contradição alta para texto fora do tema ("Lula visitou a China" vs. "Brasília é a capital do Brasil": 0,94).

## Resultados medidos — conjunto dev, **não-gold**

`data/dev_claims.jsonl`: 120 afirmações (40 triviais verdadeiras, 36 triviais falsas, 22 boatos e 22 notícias do quiz). Rótulos rascunhados pelo agente, `review_status: pending_user_review`. As regras v3 foram **ajustadas olhando esses mesmos casos**, então os números abaixo são otimistas e não estimam a precisão geral. Uma só coleta de busca por afirmação, mesmas páginas e modelos nas duas colunas. IC de Wilson 95%.

| Métrica | v0.5 (baseline) | v3 (atual) |
|---|---|---|
| Acerto (veredito = rótulo dev) | 29/120 = **24,2%** (17,4–32,6) | 74/120 = **61,7%** (52,7–69,9) |
| "Fontes divergentes" | **77**/120 | **3**/120 |
| Direção oposta (CONFIRMADO↔CONTRADITO) | 5 | 2 |
| Precisão direcional (acertos entre vereditos decisivos) | 29/34 = 85,3% (69,9–93,6) | 74/76 = **97,4%** (90,9–99,3) |
| Cobertura (vereditos decisivos) | 34/120 = 28% | 76/120 = 63% |
| Triviais verdadeiras | 6/40 | 31/40 |
| Triviais falsas | 11/36 | 23/36 |
| Boatos do quiz | 8/22 | 8/22 |
| Notícias do quiz | 4/22 | 12/22 |

Experimentos descartados, medidos no mesmo conjunto:

| Variante | Resultado | Decisão |
|---|---|---|
| Ensemble BERTimbau + MiniLMv2-L6 (média, 70/30, concordância, veto de contradição) | 72–73/120, direção oposta 4–7 | Não embarcar (+103 MB, sem ganho) |
| Sempre executar a consulta "checagem" (44 afirmações do quiz) | 20/44 com e sem | Manter só como resgate (dobraria créditos) |

Os 44 erros restantes são principalmente SEM_INFORMACAO: a busca não trouxe uma frase que afirme ou negue o fato, ou a única fonte decisiva era parcial. Os erros de direção oposta restantes vêm do NLI: "São Paulo é a capital com maior transparência" lido como apoio a "São Paulo é a capital do Brasil", e "a Terra faz uma rotação em torno de seu eixo" como apoio a "O Sol gira em torno da Terra". O retreino (`../train_nli_v2.py`, pronto e não executado) e a revisão do conjunto dev são os próximos passos.

### Wikipédia PT — medida e **ainda não promovida**

Coleta `collect-wiki` (2 páginas por afirmação, mesmas consultas do Worker), análise `analyze --mode sentence --with-wiki`, agregador v3, mesmas buscas Tavily da coluna v3:

| Variante | Acerto | "Fontes divergentes" | Direção oposta |
|---|---|---|---|
| v3 sem Wikipédia (`v3b`) | 74/120 | 3 | 2 |
| + artigo inteiro (`v3w`, o que a rota `/wiki` devolve hoje) | 73/120 | 9 | 3 |
| + só a introdução, 1.200 caracteres (`v3w1200`, `--wiki-lead 1200`) | 75/120 | 6 | 1 |

A Wikipédia corrige casos sem informação (Copa de 2002, SUS, "A independência foi em 1500" passa a contradito) e tira São Paulo-capital da direção oposta. Mas o texto enciclopédico é denso no tema e expõe o NLI. Exemplos: "Terra plana é uma concepção arcaica do formato da Terra" sai como apoio 0,95 a "A Terra é plana", e o caso crítico vira DIVERGENTE. "…foi a primeira capital do Brasil Colonial" sai como contradição 0,93. "abolição da monarquia em 1889" sai como apoio a "a independência foi proclamada em 1889". No artigo inteiro também entram frases de outro assunto que passam nos portões ("o painel do Palácio Tiradentes foi executado… em 1926").

Decisão: **não implantar `/wiki` ainda.** Antes: (1) a rota devolver só a introdução; (2) marcadores de descrédito enciclopédico ("concepção arcaica", "pseudociência", "teoria da conspiração") bloqueando apoio, como os de checagem; (3) nova medição sem regressão nos 6 casos críticos. O app já trata o 404 atual como "sem enciclopédia", então o comportamento em produção é o da coluna v3.

## Entregas

- `EvidenceScorer.swift` (novo) e `VerdictAggregator.swift` (reescrito): portões por passagem, soma por origem, DIVERGENTE só com lado oposto real. Espelham `harness/evidence.py`; `EvidenceParityTests` confere 120 passagens reais (anchors inclusos).
- Premissas por frase (`VerificationPipeline.sentencePremises`) com limpeza de créditos/migalhas; orçamento de 48 pares curtos.
- Raridade de palavras por `EmbeddingsPieceScores.bin` (Float16, 500 KB, `scripts/export-piece-scores.py`).
- Alinhamento temporal: afirmação histórica datada aceita matérias posteriores/sem data.
- `WikipediaSearchService.swift` + rota `POST /wiki` no Worker (`proxy/`, testada, **não implantada**); tipo `encyclopedia`; aviso de privacidade v3.
- Harness `harness/` (uv, Python 3.12): coleta com cache, análise baseline/v3, relatório com trace por caso, `debug_case.py`, `ensemble.py`, `export_parity_fixture.py`.
- Spike 10 (MiniLMv2-L6 em Core ML) e `nli_v2/` + `train_nli_v2.py` (retreino retomável, só smoke executado).
- Skill `.claude/skills/avaliar-verificador` e agente `.claude/agents/analista-erros-verificador`.

## Validação executada em 24/11/2026

| Verificação | Resultado |
|---|---|
| Suíte Swift `Minotaur-sTests`, iPhone 17 Pro Simulator | **175 aprovados, 0 falhas, 2 opt-in não executados** |
| Paridade Swift × Python (`EvidenceParityTests`) | 120/120 passagens |
| Ferramentas de avaliação, Python | 15 aprovados |
| Proxy (`npm test`) | 16 aprovados |
| Aparelho físico | **Não executado** nesta rodada (latência dos 48 pares e RAM pendentes) |

## Pendências

1. **Revisão do conjunto dev pelo usuário** (`data/dev_claims.jsonl`). Até lá, nada aqui é gold.
2. **Rota `/wiki`**: medida e não promovida (ver acima). Ajustar introdução + marcadores e medir de novo antes de implantar. A implantação é decisão do usuário e exige um contato do projeto no `WIKI_USER_AGENT`, porque a Wikimedia limita User-Agents sem contato.
3. **Gate físico**: latência p95 com 48 pares e RAM no iPhone 16/13.
4. **Retreino NLI** (Fase 5) e rótulos de domínio via Ollama local (exige ~15 GB livres; hoje há ~12 GB).

---

# Estado anterior — 04/11/2026

O código do plano foi implementado no verificador, proxy e ferramentas offline. **As metas de acerto ainda não foram medidas. O proxy v2 e o D1 foram implantados e verificados ao vivo em 04/11/2026.** Não houve substituição dos pesos por um modelo sem validação.

## Entregas no código

- Seleção de uma afirmação, preservação de atribuição/negação, contexto temporal e consultas curtas. ViewModel impede callbacks antigos de sobrescrever uma nova execução.
- Orçamento compartilhado: três chamadas ao buscador incluindo retries, oito artigos/quatro downloads concorrentes, coleta de rede em 11 s, prazo de análise em 15 s e 24 pares NLI. Core ML síncrono é cooperativo entre chamadas; o limite real depende do gate físico.
- Tavily basic, respostas geradas e parâmetros automáticos desativados, filtro de idioma português e allowlist controlada pelo servidor e conferida no aparelho.
- Extração estruturada: JSON-LD, autoria/datas/URLs, metadados de acesso e previews. Snippet não tem a mesma autoridade do corpo completo; paywall declarado não é recuperado pelo JSON-LD.
- BM25 + embeddings, contagem real de tokens, contexto adjacente, embedding da hipótese reutilizado e cache apenas em memória. Modelos não são invocados simultaneamente sobre a mesma instância durante cancelamento/reinício.
- Probabilidades completas/logits por passagem, conflitos preservados e votação por evidência elegível/origem. Republicações reutilizam evidência; mudanças em nomes, quantidades, negação/modalidade impedem reutilizar uma classificação indevida.
- UI com afirmação/período, contagens, origem parcial/republicações, explicações determinísticas, links e aviso fixo. Percentuais brutos de softmax removidos da apresentação de fontes.
- Privacidade v2 com reconhecimento explícito, acesso permanente à política e manifesto próprio. Verificações não são persistidas.
- Worker com reserva D1 atômica de 800 produção/200 avaliação, proteção de rajadas e falha fechada. Migração, configuração, dependências travadas e testes locais disponíveis.
- Ferramentas para importar/revisar/particionar o corpus, medir evidência + veredito, ajustar BERTimbau localmente com retomada, exportar logits, calibrar, selecionar política e bloquear promoções sem os gates.

## Validação executada

Ambiente: Xcode 27.0 (27A266a), iPhone 17 Pro Simulator com iOS 26.5. Node 25.1.0; Python 3.15 para ferramentas sem dependências de ML. O treino documentado usa ambiente separado Python 3.11/PyTorch/Transformers compatíveis com os spikes.

| Verificação | Resultado |
|---|---|
| Suíte Swift do target de testes | **161 aprovados, zero falhas, 2 opt-in não executados nesta rodada** |
| Regressão focada final de busca/extração/pipeline | **42 aprovados, zero falhas** (subconjunto, não somar à suíte geral) |
| Ferramentas de avaliação, Python | **15 aprovados** |
| Proxy com SQLite real em memória, sem rede | **11 aprovados** (incluindo compatibilidade legada e administração protegida) |
| Build Debug para simulador e build dos produtos de teste | Aprovados |
| Modelos reais + busca, suíte focada com smoke online habilitado | **36 aprovados, zero falhas, zero skips** |
| Debug arm64 assinado para iPhone | **Aprovado**, modelos e manifesto verificados no bundle |
| Inferência/paridade/pipeline físico, iPhone 16 iOS 27.2 | **Aprovados**, incluindo busca real; 161 testes locais aprovados após corrigir uma instabilidade no teste do NLTagger |
| Automação da interface física | **Um teste aprovado, zero falhas e zero skips**, após habilitar a automação no iPhone; captura no registro físico |
| Bloqueio de assets ausentes | Verificado: validação falha se pesos estão ausentes |
| Build Release arm64, assinatura desativada | Aprovado |
| Worker `wrangler deploy --dry-run` | Aprovado; seguido de upload de versão e implantação autenticada |
| Migração D1 e implantação do proxy | Concluídas; versão b5c751d7 em 100% do tráfego |
| Buscas reais de produção/avaliação | HTTP 200 nas duas faixas, um crédito cada, sem resposta LLM |
| Tipos do binding D1 | Gerados com Wrangler 4.157.0 |
| Manifesto próprio | `plutil` aprovado; presente na raiz do bundle Release |
| Whitespace/diff | `git diff --check` aprovado |

Os dois opt-in não executados na suíte geral são o replay de corpus e o smoke online. O smoke online foi habilitado e passou na rodada focada de 36 testes. Nenhum teste dos modelos foi pulado: paridade com PyTorch, inferência, seis casos críticos e pipeline com modelos reais passaram. A rodada online exercitou busca real, leitura de artigos e NLI; é uma prova funcional pontual, não avaliação de precisão geral.

O cliente de busca interrompia a chamada em 4 s, abaixo dos 4,5 s permitidos ao upstream no Worker. Uma sonda URLSession levou 4,98 s com HTTP 200. O cliente agora permite até 6 s, limitado pelo orçamento global de coleta de 11 s. Foram adicionados logs apenas de código de transporte/status/schema, sem textos ou consultas.

O aviso foi inspecionado visualmente em modo claro, modo escuro e Dynamic Type de acessibilidade máximo. O texto é rolável, a ação permanece acessível, o reconhecimento fecha a apresentação e o toolbar reabre a política com “Fechar”. O campo e a ação de verificar voltaram a ficar disponíveis após restauração dos modelos. A seleção da frase foi exercitada pela ViewModel; o smoke online confirmou resultado com artigos lidos e pares NLI reais.

O simulador não tinha marcação lexical PT utilizável: o filtro antigo descartava parágrafos jornalísticos como “sem verbo”. Foi corrigido para tratar indisponibilidade como desconhecida e preservar o texto; as regressões de ruído/navegação continuam passando.

Artefatos principais nesta máquina:

- Suíte: `/Users/henriquelacerdasilveira/Library/Developer/XcodeBuildMCP/workspaces/Minotaur-s-a2fc194a4b2f/result-bundles/test_sim_2026-11-04T20-41-02-716Z_pid79793_8d113fac.xcresult`.
- Foco final: `/Users/henriquelacerdasilveira/Library/Developer/XcodeBuildMCP/workspaces/Minotaur-s-a2fc194a4b2f/result-bundles/test_sim_2026-11-04T20-46-14-077Z_pid79793_477cb852.xcresult`.
- Build Release: `/tmp/minotaurs-verifier-release.log`.

O bundle Debug arm64 assinado com os modelos ocupa cerca de 262 MiB. Isso não valida RAM/p95 no aparelho nem distribuição Release. O tempo de 17,63 s do teste online inclui preparação fria do pipeline; a UI prepara os modelos ao abrir a tela. Não confundir essa duração com p95 de verificação em hardware.

## Etapas que dependem de recursos externos

1. **Pesos restaurados; checkpoint pendente:** os dois `.mlmodelc` foram recuperados de uma instalação antiga do app. Hash NLI coincide com a evidência do Spike 9; tokenizadores idênticos. Backup independente dos caches e restauração com SHA-256 implementados. O checkpoint PyTorch para novos treinos continua ausente. Ver [assets e procedência](../scripts/MODEL_ASSETS.md).
2. **Curadoria real:** há 204 candidatos pendentes, zero claims gold, 15 pares antigos de regressão. A base de 1.200 com revisões independentes ainda precisa ser formada. Os dois registros iniciais do catálogo também estão pendentes e não decidem resultados.
3. **Treino/calibração:** ferramentas implementadas, mas nenhum novo treino/calibração foi executado. A política permanece baseline 0,50/temperatura 1, explicitamente não calibrada. Seu critério de fonte única não foi aumentado arbitrariamente. Não afirmar que 90%/70% foram atingidos.
4. **Hardware e teste cego:** executar inferência/paridade, avaliação congelada e gates em iPhone 13 físico e mais recente. Não houve medição nova de RAM/p95. Houve smoke funcional com busca real, sem custo pago e sem estimativa de precisão. Após conexão por USB e desbloqueio, o iPhone 16 recebeu o app. Testes reais dos modelos, paridade e busca completa passaram. A rodada após correção do teste instável teve 161 testes locais aprovados; a automação inicialmente ficou bloqueada pelo modo de automação do iOS. Após habilitação pelo usuário e correção do seletor do campo no teste, o fluxo completo de UI passou, com captura da tela de resultado. Ver [registro físico](PHYSICAL_AVAILABILITY_2026-11-04.md).
5. **Cloudflare — concluído após renovação da sessão:** D1 criado/migrado e proxy v2 implantado. Plano Researcher/1.000 créditos confirmado com a secret do próprio Worker. Orçamento inicial incluiu uma busca pré-migração conservadoramente. As duas faixas responderam HTTP 200 e um crédito cada, sem respostas geradas; o contador passou a produção 2/avaliação 1. Administração sem credencial respondeu 404. A secret Tavily foi preservada e a de avaliação fica em arquivo privado fora do Git. Nenhum plano pago foi habilitado.
6. **Distribuição:** Debug assinado compilou com a equipe existente; a validação Release/Siri, publicação da política para App Store e política automatizada de robots.txt continuam pendentes. Nenhuma capacidade foi removida.

O fluxo reproduzível e os formatos de dados estão em [README da avaliação](README.md). Os dados da implantação concluída estão em [README do proxy](../proxy/README.md).


## Artefatos da correção de disponibilidade (04/11/2026)

- Suíte geral: `test_sim_2026-11-04T22-30-45-886Z_pid79793_feb8b8b7.xcresult` (161 aprovados, 2 opt-in).
- Modelos + rede real: `test_sim_2026-11-04T22-29-12-283Z_pid79793_8adc4e87.xcresult` (36 aprovados, zero skips).
- Ambos em `~/Library/Developer/XcodeBuildMCP/workspaces/Minotaur-s-a2fc194a4b2f/result-bundles/`.
- Build físico assinado: `/tmp/minotaurs-device-derived/Build/Products/Debug-iphoneos/Minotaur-s.app`.
- Log do build: `/tmp/minotaurs-device-build.log`.

Uma sonda sintética adicional, combinando e reordenando frases sobre Terra plana, produziu apoio incorreto; não foi promovida a gold nem usada para ajustar limiares. A regressão do pipeline usa a passagem pública exata já coberta pelas sondas críticas. A recuperação dos pesos resolve disponibilidade, sem eliminar as limitações semânticas conhecidas de citação/refutação do modelo baseline.


A validação manual final pela tela (simulador, busca real) terminou com 37 artigos encontrados, oito lidos, cinco usados e cinco origens. Exibiu “Fontes divergentes”, com aviso de prazo/trechos parciais. Isso confirma execução e apresentação, não correção semântica para essa afirmação; o modelo baseline ainda produziu apoio indevido em parte das passagens sobre Terra plana. O bloqueio inicial CoreDevice 4016 foi resolvido conectando e desbloqueando o aparelho. A instalação e a execução física foram confirmadas posteriormente; o registro físico acima contém os resultados e a limitação da automação de UI.


Confirmação física final: teste `Minotaur_sUITests/testVerifierWithBundledModelsAndLiveSearch()` aprovado no iPhone 16, com rede e modelos reais; um aprovado, zero falhas/skips. Artefato `/tmp/minotaurs-physical-ui-run2.xcresult`. A versão final sem plugins de testes foi reinstalada e aberta, e o runner auxiliar foi removido. Esse teste valida execução/navegação, sem atestar precisão geral ou resolver as falhas semânticas conhecidas.
