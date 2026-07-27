# Minotaur-s — Fato ou Farsa

App iOS nativo (SwiftUI) para combater desinformação de duas formas: um **quiz educativo** sobre notícias reais e falsas, e um **verificador de notícias** que confere uma afirmação digitada pelo usuário contra veículos de imprensa confiáveis, usando modelos de IA rodando **100% no dispositivo**.

O nome de exibição do app é "ato ou arsa" (com os ícones "F" formando "Fato ou Farsa").

---

## Visão geral

O app tem duas funcionalidades principais, acessadas a partir da tela inicial (`ContentView`):

### 1. Jogar (quiz "Fato ou Farsa")
O usuário recebe notícias reais (curadas em uma base local) e precisa adivinhar se são fato ou farsa, acumulando acertos/erros/pulos por partida. Inclui também uma "Pergunta do Dia", exposta como **App Intent** (integração com Siri/Atalhos), que sorteia uma pergunta por dia e a mantém fixa até a virada do dia.

### 2. Verificar Notícia
O usuário cola ou digita uma afirmação/notícia. O app:
1. gera uma query de busca a partir da afirmação;
2. busca artigos apenas em uma lista fechada (`allowlist`) de ~30 veículos de imprensa confiáveis, via API de busca (Tavily), através de um proxy que protege a chave;
3. baixa e extrai o texto principal de cada artigo (algoritmo tipo Readability sobre HTML);
4. divide o texto em trechos (*chunks*), gera embeddings de cada um e da afirmação do usuário, e seleciona os trechos mais similares semanticamente;
5. roda um modelo de **NLI** (Natural Language Inference) on-device para classificar cada trecho selecionado como `entailment` (confirma), `contradiction` (contradiz) ou `neutral` (não fala sobre);
6. agrega os resultados por artigo e por veículo em um veredito final: **Confirmado pelas fontes**, **Contradito pelas fontes**, **Fontes divergentes**, **Sem informação suficiente** ou **Não encontrado**.

O veredito nunca afirma "isso é verdade/mentira" — sempre referencia o que as fontes confiáveis dizem, com link e trecho de cada artigo citado.

A especificação técnica completa dessa feature está em [`spec.md`](./spec.md).

---

## Tecnologias

| Camada | Tecnologia |
|---|---|
| Linguagem | Swift 5 |
| UI | SwiftUI |
| iOS mínimo | 17.0 |
| Inferência de ML | Core ML (on-device, sem chamadas a LLM em nuvem) |
| Modelo de embeddings | `paraphrase-multilingual-MiniLM-L12-v2` (convertido para Core ML, INT8, ~113 MB) |
| Modelo de NLI | `MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli` (Core ML, INT8, ~103 MB, `.cpuOnly`) |
| Tokenização | [`swift-transformers`](https://github.com/huggingface/swift-transformers) (produto `Tokenizers`) |
| Parsing de HTML | [SwiftSoup](https://github.com/scinfu/SwiftSoup) |
| Álgebra vetorial | Accelerate (similaridade de cosseno) |
| Rede | `URLSession` (async/await) |
| Busca web | [Tavily](https://tavily.com) API, restrita por `include_domains` |
| Proxy de API | Cloudflare Workers (protege a chave da Tavily; o app nunca a embarca) |
| Conversão de modelos (offline) | Python + `coremltools` + `transformers` |
| Geração do projeto Xcode | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) |
| Integração com Siri/Atalhos | `AppIntents` |

Todo o processamento de linguagem da verificação (embeddings + NLI) roda localmente no aparelho — nenhum texto do usuário é enviado a um servidor de IA. A única informação que sai do dispositivo é a query de busca, enviada ao proxy que consulta a Tavily.

---

## Estrutura do projeto

```
Minotaur-s/
├── Minotaur-s/                     # target do app
│   ├── Minotaur_sApp.swift         # entry point
│   ├── Views/                      # telas (ContentView, GameView, quiz, verificador...)
│   │   └── Verificador/            # UI da feature de verificação
│   ├── Models/                     # modelos de dados (Fact, Question, GameState...)
│   │   └── Verificador/            # modelos da feature de verificação
│   ├── Services/                   # lógica de negócio, persistência, rede
│   │   └── Verificador/            # busca, extração, embeddings, NLI, agregação
│   ├── Intents/                    # App Intents (Siri/Atalhos, "Pergunta do Dia")
│   ├── Resources/
│   │   ├── Models/                 # .mlpackage (Core ML) — não versionados, ver abaixo
│   │   └── Tokenizers/             # arquivos de tokenizer versionados
│   └── Assets.xcassets/
├── Minotaur-sTests/                # testes unitários (incl. Verificador/)
├── Minotaur-sUITests/               # testes de UI
├── proxy/                          # Cloudflare Worker que protege a chave da Tavily
├── scripts/sync-models.sh          # copia os modelos Core ML já convertidos para o app
├── spikes/                         # protótipos técnicos descartáveis (não fazem parte do app)
├── project.yml                     # definição do projeto para o XcodeGen
└── spec.md                         # especificação técnica da feature "Verificar Notícia"
```

A pasta `spikes/` guarda os experimentos que validaram cada decisão técnica antes da implementação final (modelos em PT-BR, conversão para Core ML, extração de texto, scraping vs. API de busca) — é código de pesquisa, não faz parte do app publicado.

---

## Como rodar

### Pré-requisitos
- Xcode (iOS 17+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — o `.xcodeproj` é gerado a partir de `project.yml` e não é versionado

### Passos
```bash
xcodegen generate
./scripts/sync-models.sh
open Minotaur-s.xcodeproj
```

### Antes do primeiro build: modelos Core ML

O `sync-models.sh` copia os modelos já convertidos de:
- `spikes/02-coreml-latencia/build/Embeddings_int8.mlpackage`
- `spikes/02c-nli-executavel/build/L6_int8.mlpackage`

para `Minotaur-s/Resources/Models/{Embeddings,NLI}.mlpackage`.

Esses `.mlpackage` (113 MB + 103 MB) **não são versionados no git** — os `weight.bin` excedem o limite de 100 MB por arquivo do GitHub. Sem esse passo, os serviços de embeddings e NLI falham ao carregar o modelo (`.modelLoadFailed`).

> Numa máquina nova, sem os builds dos spikes 2 e 2c já existentes localmente, o script falha e aponta para rodar `convert_embeddings.py` (spike 02) e `convert_and_reference.py` (spike 02c) antes.

Os arquivos de tokenizer em `Resources/Tokenizers/` já estão versionados — nenhum passo manual é necessário em um clone normal. Só é preciso regerá-los (`spikes/07-tokenizer-parity/export_assets.py`) se houver suspeita de *drift* do modelo/tokenizer no Hugging Face.

### Proxy da Tavily

A feature de verificação depende de um endpoint próprio (Cloudflare Workers) que injeta a chave da API da Tavily — o app nunca chama a Tavily diretamente nem embarca a chave. O deploy é responsabilidade de quem mantém o projeto; instruções em [`proxy/README.md`](./proxy/README.md). Enquanto `TavilySearchService.proxyEndpoint` estiver vazio, a busca falha antes de tocar a rede.

---

## Testes

`Minotaur-sTests/Verificador/` cobre cada etapa do pipeline de verificação isoladamente (filtro de allowlist, extração de artigo, busca na Tavily, construção de query, serviços de ML, paridade de tokenizer, agregação de veredito, e o pipeline ponta a ponta), com fixtures e um `MockURLProtocol` para simular respostas de rede sem chamadas reais.

---

## Privacidade

- Nenhum backend próprio além do proxy stateless da Tavily (que não armazena nada).
- O texto digitado pelo usuário só sai do dispositivo como query de busca.
- Verificações não são persistidas — cada resultado existe apenas em memória durante a sessão.
