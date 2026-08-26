# Minotaur-s — Fato ou Farsa

Aplicativo iOS nativo, em SwiftUI, voltado à educação midiática e à checagem assistida de notícias em português. O app combina um quiz curado de **Fato ou Farsa** com um **Verificador de Notícias** que compara uma afirmação às publicações de uma lista fechada de veículos e órgãos confiáveis.

> Situação em 26 de agosto de 2026: as duas funcionalidades estão implementadas. O verificador usa busca via Tavily/Cloudflare e modelos Core ML no aparelho, apresenta um aviso de privacidade versionado na primeira entrada e mantém a política completa acessível no toolbar. A suíte completa e o build Release arm64 sem assinatura passaram; a distribuição continua bloqueada por provisioning de Siri e pelos itens externos de loja descritos em [Estado e limitações](#estado-e-limitações).

## Funcionalidades

### Quiz “Fato ou Farsa”

- apresenta notícias reais e falsas de uma base local;
- registra acertos, erros e pulos durante a partida;
- mostra uma revisão detalhada no final;
- oferece a “Pergunta do Dia” por App Intents, Siri e Atalhos;
- preserva localmente o estado necessário ao jogo.

### Verificador de Notícias

O usuário digita ou cola uma afirmação entre 15 e 1.000 caracteres. O app então:

1. usa a primeira frase, limitada a 200 caracteres, como query;
2. consulta a Tavily por meio de um proxy Cloudflare Workers, restringindo a busca a 31 domínios que representam 30 veículos/órgãos;
3. aplica novamente a allowlist no aparelho e mantém até cinco resultados;
4. baixa os artigos em paralelo e extrai o texto principal com SwiftSoup;
5. remove trechos sem valor proposicional e divide o conteúdo em chunks;
6. usa embeddings para selecionar até três chunks semanticamente relevantes por artigo;
7. classifica cada par `(chunk, afirmação)` com NLI on-device;
8. agrega os votos em **Confirmado pelas fontes**, **Contradito pelas fontes**, **Fontes divergentes**, **Sem informação suficiente** ou **Não encontrado**.

O resultado sempre informa o que as fontes encontradas dizem. Ele não declara que uma afirmação é uma verdade ou mentira absoluta e exibe, para cada fonte, trecho, atribuição e link do artigo original.

Na primeira abertura do Verificador, uma sheet não dispensável informa que somente a primeira frase, limitada a 200 caracteres, é enviada ao proxy e à Tavily. O reconhecimento é versionado e só é salvo ao tocar em “Entendi e continuar”. A política completa permanece disponível pelo botão de mão no toolbar.

A especificação detalhada está em [`spec.md`](./spec.md).

## Arquitetura do verificador

```text
entrada
  → SearchQueryBuilder
  → TavilySearchService (proxy Cloudflare)
  → AllowlistFilter
  → ArticleExtractor
  → TextChunker + ChunkQualityFilter
  → EmbeddingService (cosseno ≥ 0,25; top 3)
  → NLIService (confiança ≥ 0,50)
  → VerdictAggregator
  → VerificationResult
```

O `VerificationPipeline` coordena as etapas. A UI acessa o pipeline por `VerificationViewModel`; os serviços não conhecem a tela nem coordenam uns aos outros.

## Stack atual

| Camada | Tecnologia |
|---|---|
| Linguagem e UI | Swift 5 + SwiftUI |
| Deployment target | iOS 17.0 |
| Inferência | Core ML, on-device, `.cpuOnly` para o NLI |
| Embeddings | `paraphrase-multilingual-MiniLM-L12-v2`, INT8, ~113 MB |
| NLI | BERTimbau-base, fine-tune próprio em PLUE/MNLI, INT8, ~104 MB |
| Tokenização | XLM-R via `swift-transformers` para embeddings; WordPiece próprio para NLI |
| HTML | SwiftSoup |
| Vetores | Accelerate |
| Rede | `URLSession` com async/await |
| Busca | Tavily `basic`, por proxy Cloudflare Workers |
| Projeto | Xcode project versionado; `project.yml` existe, mas está incompleto em relação ao `.xcodeproj` atual |
| Testes | Swift Testing + fixtures e `MockURLProtocol` |

Os modelos somam aproximadamente 217 MB; os dois tokenizers versionados somam aproximadamente 17 MB. Nenhum serviço de nuvem produz o veredito: embeddings e NLI rodam localmente. A primeira frase, limitada a 200 caracteres, sai do aparelho como query de busca, passa pelo proxy stateless e chega à Tavily; a Tavily pode reter queries conforme sua política.

## Estrutura

```text
Minotaur-s/
├── Minotaur-s/
│   ├── Views/                  # tela inicial, jogo, revisão e verificador
│   ├── Models/                 # domínio do jogo e do verificador
│   ├── Services/               # persistência, dados locais e pipeline de verificação
│   ├── Intents/                # Siri/Atalhos e Pergunta do Dia
│   ├── Resources/
│   │   ├── Models/             # Core ML ignorado pelo Git; gerado por sync-models.sh
│   │   ├── Tokenizers/         # tokenizers e mapa de labels versionados
│   │   └── PrivacyInfo.xcprivacy
│   └── Assets.xcassets/
├── Minotaur-sTests/            # testes unitários e de integração local
├── Minotaur-sUITests/          # target de testes de UI
├── proxy/                      # Cloudflare Worker da Tavily
├── scripts/sync-models.sh      # sincroniza os modelos validados para o bundle
├── spikes/                     # evidências técnicas e scripts de pesquisa (Spikes 1–9)
├── Minotaur-s.xcodeproj/       # projeto Xcode usado atualmente
├── project.yml                 # definição XcodeGen ainda não sincronizada com o projeto atual
├── spec.md                     # especificação do Verificador de Notícias
└── CLAUDE.md                   # regras operacionais para agentes de código
```

`spikes/` contém pesquisa reproduzível, resultados de conversão, gates de aparelho e fine-tune. Esses arquivos não fazem parte do target do aplicativo.

## Como executar

### Pré-requisitos

- macOS com Xcode capaz de compilar para iOS 17 ou superior;
- dependências Swift Package Manager resolvidas pelo Xcode;
- builds locais dos dois modelos Core ML, que não são versionados por excederem o limite de arquivo do GitHub.

### Preparação

```bash
./scripts/sync-models.sh
open Minotaur-s.xcodeproj
```

O script copia:

- `spikes/02-coreml-latencia/build/Embeddings_int8.mlpackage`;
- `spikes/09-nli-base-search/build/trained/bertimbau_base_plue_dynamic512_int8.mlpackage`.

Os destinos são `Minotaur-s/Resources/Models/Embeddings.mlpackage` e `NLI.mlpackage`. Sem os pesos completos, o verificador permanece indisponível e reporta `.modelLoadFailed` sem derrubar o restante do app.

Se os builds dos spikes não existirem na máquina, execute primeiro os scripts de conversão indicados por `scripts/sync-models.sh`.

> Não rode `xcodegen generate` no estado atual: `project.yml` ainda não representa as dependências SPM, o nome de exibição e todas as configurações presentes no `.xcodeproj` versionado.

### Busca web

O endpoint do Worker está configurado em `TavilySearchService.proxyEndpoint`. A chave `TAVILY_API_KEY` permanece somente como secret do Cloudflare Worker; nunca deve ser adicionada ao app ou ao repositório. O contrato do proxy está documentado em [`proxy/README.md`](./proxy/README.md).

## Testes e evidências

Os testes de `Minotaur-sTests/Verificador/` cobrem validação e apresentação, allowlist, busca e retry, extração, chunking, qualidade de chunks, tokenização, paridade Core ML, agregação, cancelamento e pipeline.

Auditoria final de release executada em 10 de agosto de 2026:

- **143/143** testes Swift Testing e **6/6** testes de UI no iPhone 16 Pro Simulator com iOS 18.6;
- **28/28** testes focados de NLI/tokenização no iPhone 16;
- build e lançamento no simulador e no aparelho: aprovados;
- build Release arm64 sem assinatura: aprovado.
- `.app` Release arm64 sem assinatura: **267.536 KiB (261 MiB)**, com exatamente dois recursos Core ML compilados (`Embeddings.mlmodelc` e `NLI.mlmodelc`);
- versão **1.0**, build **1**, deployment target iOS **17.0**, bundle identifier `com.julia.fatoufarsa2025` e AppIcon 1024×1024 válidos no build;
- ATS padrão, sem exceções de transporte; nenhum segredo de aplicação encontrado na varredura dos arquivos versionados.

Os detalhes e caminhos dos result bundles estão em [`spikes/09-nli-base-search/INTEGRACAO_RESULTADO.md`](./spikes/09-nli-base-search/INTEGRACAO_RESULTADO.md).

Validação incremental de privacidade executada em 26 de agosto de 2026, preservando a auditoria histórica acima:

- **149/149** testes Swift Testing e **8/8** testes de UI no iPhone 16e Simulator com iOS 18.6;
- teste de UI da primeira entrada, reconhecimento explícito, acesso permanente e relançamento aprovado;
- modo claro e modo escuro, Dynamic Type de acessibilidade XXXL e rótulo acessível “Política de privacidade” verificados no Simulator;
- `PrivacyInfo.xcprivacy` aprovado por `plutil`, copiado sem alteração para a raiz do `.app` Release;
- build Release arm64 sem assinatura aprovado; `.app` com **268.516 KiB**, incluindo o manifesto próprio.

### Checklist final RF/NF/CA

- **RF:** RF-01–RF-10 possuem cobertura automatizada da lógica e apresentação; a suíte completa passou. Permanecem sem comprovação ponta a ponta de produção o paywall parcial, o retry por artigo e as respostas reais de cota/rate-limit da Tavily.
- **NF:** arquitetura, concorrência, inferência on-device, limite de tamanho do `.app`, RAM/latência no iPhone 16, HTTPS/ATS, ausência de chave no app, aviso local, política no app e manifesto próprio estão comprovados. Continuam pendentes o gate direto no iPhone 13, o tempo total com rede real, a URL pública da política para a ficha da App Store, `robots.txt` e o tamanho de distribuição assinado.
- **CA:** CA-01–CA-13 possuem testes automatizados correspondentes e passaram; CA-01 não teve nesta auditoria uma medição ponta a ponta com busca/artigos reais abaixo de 15 s, e CA-05 não comprova empiricamente paywall parcial.

## Estado e limitações

- O BERTimbau-base integrado marcou **13/15** nos pares adversariais reais e **6/6** nos casos críticos de Terra plana e vacina; os dois erros residuais envolvem nuances da alegação de “cura do câncer”.
- A estabilidade a pequenas variações de afirmações curtas ficou em **2/3 famílias**. O aviso de análise automatizada e os links para as fontes continuam obrigatórios.
- O gate físico mediu até **383,7 MB** de memória residente e **66,5 ms** aquecidos a 512 tokens no iPhone 16. A validação direta no iPhone 13 ainda é recomendada antes do lançamento.
- O app Release arm64 sem assinatura ocupou 267.536 KiB (261 MiB) descompactados. Archive, `.ipa` e estimativa da App Store não puderam ser medidos sem assinatura válida.
- O archive assinado falha porque `iOS Team Provisioning Profile: *` não inclui a capability Siri nem o entitlement `com.apple.developer.siri`. É necessário entrar no Xcode com a conta Apple da equipe `2DK23BZ7KB` e regenerar/baixar o profile de `com.julia.fatoufarsa2025` com Siri habilitada.
- A política está disponível offline dentro do app, mas ainda precisa ser publicada em uma URL pública para o campo exigido pelo App Store Connect.
- Política de `robots.txt`, paywall parcial e retry por artigo continuam pendências de conformidade/robustez.
- O verificador depende da disponibilidade e da cota da Tavily e do proxy.

## Privacidade

- verificações não são persistidas;
- a afirmação completa e o resultado ficam apenas em memória;
- o proxy é stateless, não possui KV, D1 ou cache de conteúdo e não faz logging explícito do corpo;
- o texto completo fica no aparelho; apenas a primeira frase, limitada a 200 caracteres, é transmitida ao proxy e à Tavily;
- a infraestrutura da Cloudflare pode processar metadados técnicos, e a Tavily pode reter queries e usá-las para melhoria conforme suas políticas;
- os artigos são baixados diretamente dos sites das fontes; abri-los no Safari é opcional;
- não há chamadas a LLM ou a outro serviço de inferência em nuvem;
- não há anúncios, tracking, analytics ou crash reporting de terceiros;
- trechos exibidos têm no máximo 300 caracteres, com atribuição e link para o original.

A política completa, em vigor desde 26/08/2026, está no próprio app. Políticas externas: [Tavily](https://www.tavily.com/privacy), [Cloudflare](https://www.cloudflare.com/privacypolicy/) e [Apple](https://www.apple.com/legal/privacy/).
