# Minotaur-s — Fato ou Farsa

Aplicativo iOS em SwiftUI para educação midiática: quiz curado, Pergunta do Dia/Siri/Atalhos e Verificador de Notícias em português brasileiro.

## Verificador — evolução v0.5 (04/11/2026)

O verificador compara uma afirmação com evidências de fontes selecionadas. Embeddings e NLI executam no iPhone via Core ML; não há API de LLM nem geração de explicações por IA.

- Uma afirmação por vez; textos com várias frases exigem escolha, e contexto dependente exige reformulação.
- Até três consultas de 200 caracteres, extraídas da afirmação selecionada, incluindo datas relativas resolvidas localmente.
- Busca oficial Tavily `basic`, sem resposta gerada, restrita à allowlist de 31 domínios.
- Até 20 candidatos por consulta; leitura de até oito artigos, quatro downloads concorrentes, JSON-LD/metadados e indicação de conteúdo parcial.
- Recuperação BM25 + embeddings, janelas curtas e expansão com parágrafos adjacentes, contando tokens reais.
- Até 24 pares NLI; uma hipótese/embedding compartilhada durante a sessão.
- Snippets isolados, previews e fontes de outro período não decidem. Republicações são agrupadas; conflitos válidos continuam visíveis, mesmo quando há maioria.
- Cinco vereditos referenciados às fontes: Confirmado, Contradito, Fontes divergentes, Sem informação suficiente e Não encontrado.
- Resultado apresenta afirmação/período, evidências/links, contagens e limitações. Não exibe softmax como porcentagem de verdade.
- Orçamento monotônico de 15 s, encerrando coleta de rede em 11 s. Prazo/cancelamento são verificados entre inferências; o limite efetivo precisa ser medido em hardware real.

O aviso de privacidade v2 exige reconhecimento explícito. O estado desse reconhecimento é salvo localmente; verificações não têm histórico. Queries passam pelo Worker/Tavily e podem ser tratadas pelo provedor conforme sua política. D1 guarda somente contadores mensais/rajadas, sem textos ou resultados. A política permanece acessível pelo botão de privacidade.

## Arquitetura

`ClaimAnalyzer → plano de busca → busca/leitura concorrentes → artigo estruturado → recuperação híbrida → NLI → agregação por evidências → resultado`

`VerificationPipeline` coordena serviços por protocolos. `VerificationRunner` mantém modelos/inferência fora da main thread; a ViewModel apresenta seleção, progresso, cancelamento, resultado e erros. As demais funcionalidades do app não foram alteradas.

| Camada | Tecnologia |
|---|---|
| UI / deployment | SwiftUI, Swift 5, iOS 17+ |
| Embeddings | paraphrase-multilingual-MiniLM-L12-v2, Core ML INT8 |
| NLI | BERTimbau-base ajustado no Spike 9 em PLUE/MNLI, Core ML INT8/FP16, CPU |
| Tokenização | XLM-R para embeddings; WordPiece próprio para NLI |
| HTML / vetores | SwiftSoup / Accelerate |
| Rede / busca | URLSession async, Tavily via Cloudflare Workers |
| Cota | D1, reserva atômica por tentativa: 800 produção + 200 avaliação/mês |

## Como executar

Abrir `Minotaur-s/Minotaur-s.xcodeproj`. Não regenerar pelo XcodeGen: `project.yml` ainda não representa todas as dependências/configurações do projeto versionado.

Os pesos Core ML não são versionados, mas foram recuperados nesta máquina. O build verifica presença e SHA-256 dos modelos e tokenizadores no projeto e no app empacotado. Para restaurar o backup local, execute `bash Minotaur-s/scripts/sync-models.sh`. Veja [procedência e restauração](Minotaur-s/scripts/MODEL_ASSETS.md).

```sh
cd Minotaur-s
./scripts/sync-models.sh
open Minotaur-s.xcodeproj
```

O script restaura os dois `.mlmodelc` do backup em `~/Library/Application Support/Minotaur-s/models/bertimbau-base-plue-spike9/`. Ausência ou corrupção dos pesos impede concluir o build. Não substituir o NLI por uma base sem cabeça treinada.

A configuração de busca fica em `TavilySearchService.proxyEndpoint`. O app nunca recebe a chave da Tavily. Para testes/deploy do proxy e reconciliação de cota, consultar [proxy/README.md](Minotaur-s/proxy/README.md). O proxy v2 e o contador D1 estão ativos em produção desde 04/11/2026, na mesma URL configurada no app.

## Avaliação e modelo

[Especificação v0.5](Minotaur-s/spec.md) · [Fluxo de curadoria/treino/avaliação](Minotaur-s/evaluation/README.md)

`evaluation/` contém validação/particionamento sem vazamento, métricas de veredito+evidência, treino local retomável, calibração, seleção de política e gate de promoção. Há **204 candidatos pendentes de revisão, zero claims gold** e 15 pares conhecidos de regressão. Duas checagens públicas foram preparadas para o catálogo embarcado, mas ficam inativas até revisão independente.

A meta é obter 1.200 afirmações revisadas (600 treino, 300 calibração e 300 teste cego), precisão direcional ≥90% e cobertura dos casos solucionáveis ≥70%. Esses valores **não foram demonstrados**. A política baseline mantém temperatura 1 e piso 0,50, identificados como não calibrados; nenhuma calibração ou novo checkpoint foi inventado.

O resultado histórico de 13/15 pares adversariais do BERTimbau-base não estima precisão geral. As falhas conhecidas de modalidade/atribuição/generalização estão documentadas em [ERROS_RESIDUAIS_NLI.md](Minotaur-s/spikes/09-nli-base-search/ERROS_RESIDUAIS_NLI.md). Os dados conhecidos não podem se tornar teste cego.

## Validação e pendências

A implementação inclui testes de seleção, consultas/tempo, cota compartilhada, extração estruturada, conteúdo parcial, republicações, conflito, política e metadados. O proxy é testado com SQLite real, sem rede, incluindo concorrência e limites. O diretório de avaliação tem testes sem dependências de ML. Consultar [registro da implementação](Minotaur-s/evaluation/IMPLEMENTATION_STATUS.md) para resultados executados e limites da comprovação.

Pendências externas:

- Recuperar o checkpoint PyTorch original para novos treinos. Os pesos Core ML estão restaurados e os testes de inferência/paridade passaram; o replay com corpus revisado continua pendente.
- Revisão humana e ampliação do corpus, novo treino/calibração e teste cego.
- Gates físicos no iPhone 13 e aparelho mais recente, incluindo RAM/latência frias e consecutivas. Dados do iPhone 16 de agosto não validam automaticamente o novo pipeline.
- Política automatizada de robots.txt, URL pública de privacidade para loja e distribuição assinada. Preservar Siri/entitlements/equipe; não contornar o provisioning removendo capacidades.

## Privacidade

Textos e resultados permanecem em memória da sessão; somente consultas reduzidas são transmitidas para busca. Sem API de inferência remota, publicidade, tracking ou coleta de verificações dos usuários para treinamento. Artigos são acessados nos sites das fontes, com trechos limitados e atribuição. A infraestrutura e o buscador podem tratar metadados e consultas segundo suas próprias políticas: [Tavily](https://www.tavily.com/privacy), [Cloudflare](https://www.cloudflare.com/privacypolicy/). O manifesto do app declara as APIs locais e o conteúdo de consulta usado para a funcionalidade.
